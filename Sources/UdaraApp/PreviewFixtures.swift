import SwiftUI

#if DEBUG
@MainActor enum PreviewFixtures {
    static let date = Date(timeIntervalSince1970: 1_800_000_000)
    static func observation(value: Double?, name: String, overdue: Bool = false, malaysia: Bool = false) -> CityForecast {
        let scale = "MY_API"
        let o = StationObservation(source: "doe",
            index: .init(value: value ?? 50, scale: scale, metric: "overall"),
            pm25Index: value.map { .init(value: $0, scale: scale, metric: "pm25") },
            pm2524hConcentration: malaysia ? .init(value: 12.3, unit: "µg/m³", averagingPeriod: "24h") : nil,
            station: .init(id: "fixture", name: "\(name) station", latitude: 3.1, longitude: 101.5, distanceKm: 3.2),
            observedAt: date.addingTimeInterval(-1800), fetchedAt: date.addingTimeInterval(-300),
            attribution: [.init(name: "DOE Malaysia", url: URL(string: "https://eqms.doe.gov.my/")!)])
        return CityForecast(fetchedAt: date.addingTimeInterval(overdue ? -900 : -300), samples: [], metric: "station_pm25_v1", observation: o)
    }
    static func store(empty: Bool = false, overdue: Bool = false, unavailable: Bool = false, loading: Bool = false, error: Bool = false) -> AppStore {
        let names = ["Kuala Lumpur", "George Town", "Ipoh", "Kuching", "Johor Bahru", "A very long city name in a beautiful valley"]
        let values: [Double] = [32, 74, 122, 168, 245, 340]
        let cities = empty ? [] : names.enumerated().map {
            SavedCity(id: $0.offset, name: $0.element, region: "Region", country: "Country", latitude: 3.139, longitude: 101.6869, timezone: "Asia/Kuala_Lumpur")
        }
        var state = RepositorySnapshot(cities: cities, forecasts: Dictionary(uniqueKeysWithValues: cities.map {
            ($0.id, observation(value: unavailable ? nil : values[$0.id], name: $0.name, overdue: overdue, malaysia: $0.id < 2))
        }))
        if !empty {
            state.currentLocation = SavedCity(id: -1, name: "Petaling Jaya", region: "", country: "Detected location", latitude: 3.11, longitude: 101.61, timezone: "Asia/Kuala_Lumpur")
            state.forecasts[-1] = observation(value: 48, name: "Petaling Jaya", malaysia: true)
        }
        let persistence = MemoryPersistence()
        try! persistence.save(state)
        let repository = try! ForecastRepository(provider: PreviewProvider(), searchProvider: PreviewProvider(), persistence: persistence, clock: FixedClock(now: date))
        let store = AppStore(repository: repository, clock: FixedClock(now: date), fixture: state, fixtureRefreshing: loading)
        store.locationPhase = empty ? .notRequested : .located
        if ProcessInfo.processInfo.arguments.contains("--location-denied") { store.locationPhase = .denied }
        if ProcessInfo.processInfo.arguments.contains("--location-unavailable") { store.locationPhase = .unavailable }
        if error { store.errorMessage = "You appear to be offline. Recent station readings remain available." }
        return store
    }
}
struct PreviewProvider: AirQualityProvider, CitySearchProvider {
    func forecast(for city: SavedCity) async throws -> CityForecast { throw URLError(.notConnectedToInternet) }
    func search(_ query: String) async throws -> [SavedCity] {
        [SavedCity(id: 100, name: "Kuala Lumpur", region: "Kuala Lumpur", country: "Malaysia", latitude: 3.139, longitude: 101.6869, timezone: "Asia/Kuala_Lumpur")]
    }
}
#Preview("All categories · Light") { MenuView(store: PreviewFixtures.store()).preferredColorScheme(.light) }
#Preview("All categories · Dark") { MenuView(store: PreviewFixtures.store()).preferredColorScheme(.dark) }
#Preview("First launch") { MenuView(store: PreviewFixtures.store(empty: true)) }
#Preview("Update overdue") { MenuView(store: PreviewFixtures.store(overdue: true)) }
#Preview("Unavailable / offline") { MenuView(store: PreviewFixtures.store(unavailable: true)) }
#Preview("Loading") { MenuView(store: PreviewFixtures.store(unavailable: true, loading: true)) }
#Preview("Offline error") { MenuView(store: PreviewFixtures.store(overdue: true, error: true)) }
#Preview("Reduced transparency") { MenuView(store: PreviewFixtures.store()).environment(\.udaraReduceTransparencyOverride, true) }
#Preview("Location denied") {
    let store = PreviewFixtures.store()
    store.locationPhase = .denied
    return MenuView(store: store)
}
#Preview("Location unavailable") {
    let store = PreviewFixtures.store()
    store.locationPhase = .unavailable
    return MenuView(store: store)
}
#Preview("City search") { CitySearchView(store: PreviewFixtures.store(empty: true)).frame(width: 360) }
#Preview("Settings") { SettingsContent(store: PreviewFixtures.store()) }
#Preview("City row") { CityRowView(status: PreviewFixtures.store().rows[0]).frame(width: 360) }
#endif
