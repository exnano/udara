import AppKit
import CoreLocation
import MapKit
import SwiftUI

@MainActor enum AppEnvironment {
    static let store: AppStore = {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--preview-host") || ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return PreviewFixtures.store(empty: ProcessInfo.processInfo.arguments.contains("--empty"))
        }
        #endif
        let provider = OpenMeteoProvider()
        do {
            return AppStore(repository: try ForecastRepository(provider: provider, searchProvider: provider, persistence: DiskPersistence.applicationSupport()))
        } catch {
            let repository = try! ForecastRepository(provider: provider, searchProvider: provider, persistence: MemoryPersistence())
            let store = AppStore(repository: repository)
            store.startupWarning = "Saved data could not be read and was preserved. Changes in this session will not be saved. \(error.localizedDescription)"
            return store
        }
    }()
}
@main struct UdaraApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var store = AppEnvironment.store
    var body: some Scene {
        MenuBarExtra {
            MenuView(store: store)
        } label: {
            Image(nsImage: MenuBarGlyph.image(reading: store.highest, style: store.menuBarIconStyle))
                .accessibilityIdentifier("udaraMenuBar")
                .accessibilityLabel(store.highest.map { "Udara, estimated US AQI \($0.value), \($0.category.title)" } ?? "Udara, AQI unavailable")
        }.menuBarExtraStyle(.window)
    }
}
@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    private var task: Task<Void, Never>?
    private var locationController: CurrentLocationController?
    private var observers: [NSObjectProtocol] = []
    #if DEBUG
    private var previewWindow: NSWindow?
    #endif
    func applicationDidFinishLaunching(_ notification: Notification) {
        let store = AppEnvironment.store
        task = Task { await store.run() }
        if !store.isFixture { locationController = CurrentLocationController(store: store) }
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.locationController?.refresh()
                await AppEnvironment.store.wake()
            }
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSNotification.Name.NSSystemClockDidChange, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.locationController?.refresh()
                await AppEnvironment.store.wake()
            }
        })
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--preview-host") {
            if ProcessInfo.processInfo.arguments.contains("--light") { NSApp.appearance = NSAppearance(named: .aqua) }
            if ProcessInfo.processInfo.arguments.contains("--dark") { NSApp.appearance = NSAppearance(named: .darkAqua) }
            NSApp.setActivationPolicy(.regular)
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 360, height: 660), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "Udara Preview"
            window.contentView = NSHostingView(rootView: MenuView(store: store)
                .environment(\.udaraReduceTransparencyOverride, ProcessInfo.processInfo.arguments.contains("--reduced-transparency") ? true : nil))
            window.center(); window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            previewWindow = window
        }
        #endif
    }
    func applicationWillTerminate(_ notification: Notification) {
        task?.cancel()
        locationController?.stop()
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }
}

/// CLLocationManager is created on the main actor and delivers delegates on that run loop.
/// One-shot city-scale fixes; no continuous tracking and no permission prompts from previews.
@MainActor final class CurrentLocationController: NSObject, @preconcurrency CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private let store: AppStore
    private var timer: Task<Void, Never>?
    private var timeout: Task<Void, Never>?
    private var geocoding: Task<Void, Never>?
    private var request: MKReverseGeocodingRequest?
    private var generation = UUID()
    private var requesting = false

    init(store: AppStore) {
        self.store = store
        super.init()
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        manager.delegate = self
        store.requestLocation = { [weak self] in self?.refresh(askPermission: true) }
        timer = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(3600)) } catch { return }
                self?.refresh()
            }
        }
    }
    func refresh(askPermission: Bool = false) {
        guard !requesting else { return }
        switch manager.authorizationStatus {
        case .notDetermined:
            if askPermission { manager.requestWhenInUseAuthorization() }
        case .denied, .restricted:
            invalidate()
            Task { await store.locationUnavailable(.denied) }
            if askPermission, let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices") {
                NSWorkspace.shared.open(url)
            }
        case .authorizedAlways, .authorizedWhenInUse:
            requesting = true
            store.locationPhase = .locating
            manager.requestLocation()
            timeout = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(25)) } catch { return }
                guard let self else { return }
                self.invalidate()
                await self.store.locationUnavailable(.unavailable)
            }
        @unknown default:
            Task { await store.locationUnavailable(.unavailable) }
        }
    }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        invalidate()
        refresh()
    }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard requesting, let fix = locations.last,
              fix.horizontalAccuracy >= 0, fix.horizontalAccuracy <= 10_000,
              abs(fix.timestamp.timeIntervalSinceNow) < 300 else { return }
        manager.stopUpdatingLocation()
        guard geocoding == nil else { return }
        let token = generation
        // Round coordinates to roughly kilometre-scale before requesting external services.
        let latitude = (fix.coordinate.latitude * 100).rounded() / 100
        let longitude = (fix.coordinate.longitude * 100).rounded() / 100
        let approximate = CLLocation(latitude: latitude, longitude: longitude)
        request = MKReverseGeocodingRequest(location: approximate)
        geocoding = Task { [weak self] in
            guard let self else { return }
            let items = try? await self.request?.mapItems
            guard !Task.isCancelled, self.generation == token else { return }
            let area = items?.first?.addressRepresentations?.cityName
            let city = SavedCity(id: -1, name: area ?? "Nearby area", region: "", country: "Detected location", latitude: latitude, longitude: longitude, timezone: TimeZone.current.identifier)
            self.timeout?.cancel(); self.timeout = nil
            self.requesting = false; self.geocoding = nil; self.request = nil
            await self.store.updateLocation(city)
        }
    }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        guard requesting else { return }
        invalidate()
        let denied = (error as? CLError)?.code == .denied
        Task { await store.locationUnavailable(denied ? .denied : .unavailable) }
    }
    private func invalidate() {
        generation = UUID()
        requesting = false
        manager.stopUpdatingLocation()
        timeout?.cancel(); timeout = nil
        request?.cancel(); request = nil
        geocoding?.cancel(); geocoding = nil
    }
    func stop() { invalidate(); timer?.cancel(); timer = nil }
}
