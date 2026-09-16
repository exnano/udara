import AppKit
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
            Label(store.highest.map { String($0.value) } ?? "—", systemImage: store.highest?.category.symbol ?? "wind")
                .foregroundStyle(store.highest?.category.color ?? .secondary)
                .accessibilityLabel(store.highest.map { "Udara, estimated US AQI \($0.value), \($0.category.title)" } ?? "Udara, AQI unavailable")
        }.menuBarExtraStyle(.window)
    }
}
@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    private var task: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []
    #if DEBUG
    private var previewWindow: NSWindow?
    #endif
    func applicationDidFinishLaunching(_ notification: Notification) {
        let store = AppEnvironment.store
        task = Task { await store.run() }
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in await AppEnvironment.store.wake() }
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSNotification.Name.NSSystemClockDidChange, object: nil, queue: .main) { _ in
            Task { @MainActor in await AppEnvironment.store.wake() }
        })
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--preview-host") {
            if ProcessInfo.processInfo.arguments.contains("--light") { NSApp.appearance = NSAppearance(named: .aqua) }
            if ProcessInfo.processInfo.arguments.contains("--dark") { NSApp.appearance = NSAppearance(named: .darkAqua) }
            NSApp.setActivationPolicy(.regular)
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 360, height: 660), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "Udara Preview"
            window.contentView = NSHostingView(rootView: MenuView(store: store))
            window.center(); window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            previewWindow = window
        }
        #endif
    }
    func applicationWillTerminate(_ notification: Notification) {
        task?.cancel()
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }
}
