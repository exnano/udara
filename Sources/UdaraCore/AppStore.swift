import Foundation
import Observation

@MainActor @Observable final class AppStore {
    private(set) var state = RepositorySnapshot()
    private(set) var now: Date
    private(set) var isRefreshing = false
    var searchResults: [SavedCity] = []
    private(set) var isSearching = false
    var startupWarning: String?
    var errorMessage: String?
    var searchError: String?
    var locationPhase: LocationPhase = .notRequested
    @ObservationIgnored private var locationRevision = UUID()
    @ObservationIgnored var requestLocation: (() -> Void)?
    var currentLocationRow: CityStatus? {
        guard locationPhase == .located, let city = state.currentLocation else { return nil }
        return CityStatus(city: city, forecast: state.forecasts[-1], now: now)
    }
    func updateLocation(_ city: SavedCity) async {
        let revision = UUID(); locationRevision = revision
        do {
            try await repository.setCurrentLocation(city)
            guard locationRevision == revision else { return }
            locationPhase = .located
            await load()
            await refresh()
        } catch {
            guard locationRevision == revision else { return }
            errorMessage = error.localizedDescription; locationPhase = .unavailable
        }
    }
    func locationUnavailable(_ phase: LocationPhase) async {
        locationRevision = UUID()
        locationPhase = phase
        do {
            if phase == .denied { try await repository.setCurrentLocation(nil) }
            else { await repository.suspendCurrentLocation() }
            await load()
        }
        catch { errorMessage = error.localizedDescription }
    }
    @ObservationIgnored private let repository: ForecastRepository
    @ObservationIgnored private let clock: any AppClock
    @ObservationIgnored private var searchGeneration = UUID()
    @ObservationIgnored private var running = false
    @ObservationIgnored private var refreshAgain = false
    @ObservationIgnored let isFixture: Bool

    init(repository: ForecastRepository, clock: any AppClock = SystemClock(), fixture: RepositorySnapshot? = nil, fixtureRefreshing: Bool = false) {
        self.repository = repository; self.clock = clock; now = clock.now
        isFixture = fixture != nil
        isRefreshing = fixtureRefreshing
        if let fixture { state = fixture }
    }
    var rows: [CityStatus] { CityStatus.sorted(cities: state.cities, forecasts: state.forecasts, now: now) }
    var menuBarIconStyle: MenuBarIconStyle { state.menuBarIconStyle ?? .udara }
    func setMenuBarIconStyle(_ style: MenuBarIconStyle) async {
        do { try await repository.setMenuBarIconStyle(style); await load() }
        catch { errorMessage = error.localizedDescription }
    }
    var highest: AQIReading? { (rows.compactMap(\.reading) + [currentLocationRow?.reading].compactMap { $0 }).max { $0.value < $1.value } }
    var nextDownload: Date? {
        (state.cities + (currentLocationRow.map { [$0.city] } ?? [])).compactMap { city in
            if let retry = state.retries[city.id] { return retry.nextAttempt }
            return state.scheduled[city.id]
        }.min()
    }
    func load() async { state = await repository.snapshot(); now = clock.now }
    func refresh() async {
        guard !isFixture else { return }
        if isRefreshing { refreshAgain = true; return }
        isRefreshing = true
        defer { isRefreshing = false }
        repeat {
            refreshAgain = false
            state = await repository.refreshDue()
            now = clock.now
            errorMessage = await repository.persistenceWarning
        } while refreshAgain
    }
    func add(_ city: SavedCity) async {
        do {
            try await repository.add(city)
            await load()
            await refresh()
        } catch { errorMessage = error.localizedDescription }
    }
    func remove(_ city: SavedCity) async {
        do { try await repository.remove(city.id); await load() }
        catch { errorMessage = error.localizedDescription }
    }
    func search(_ query: String) async {
        let generation = UUID(); searchGeneration = generation
        searchResults = []; searchError = nil
        guard query.trimmingCharacters(in: .whitespacesAndNewlines).count >= 3 else { isSearching = false; return }
        isSearching = true
        defer { if searchGeneration == generation { isSearching = false } }
        do {
            try await Task.sleep(for: .milliseconds(400))
            let results = try await repository.search(query)
            try Task.checkCancellation()
            if searchGeneration == generation { searchResults = results }
        } catch is CancellationError {} catch {
            if searchGeneration == generation { searchError = error.localizedDescription }
        }
    }
    /// Starts once for the application lifetime, not once per dropdown opening.
    func run() async {
        guard !running, !isFixture else { return }
        running = true
        defer { running = false }
        await load()
        while !Task.isCancelled {
            now = clock.now
            await refresh()
            // Wake at the next minute; this includes every hour boundary.
            let delay = 60 - clock.now.timeIntervalSince1970.truncatingRemainder(dividingBy: 60)
            do { try await Task.sleep(for: .seconds(max(1, delay))) } catch { return }
        }
    }
    func wake() async { now = clock.now; await refresh() }
}
