import SwiftUI

#if DEBUG
@MainActor enum PreviewFixtures {
    static let date = Date(timeIntervalSince1970: 1_800_000_000)
    static func store(empty: Bool = false, overdue: Bool = false, unavailable: Bool = false, loading: Bool = false, error: Bool = false) -> AppStore {
        let names = ["Kuala Lumpur", "George Town", "Singapore", "Chiang Mai", "Jakarta", "A very long city name in a beautiful valley"]
        let values: [Double] = [32, 74, 122, 168, 245, 340]
        let cities = empty ? [] : names.enumerated().map {
            SavedCity(id: $0.offset, name: $0.element, region: "Region", country: "Country", latitude: 3.139, longitude: 101.6869, timezone: "Asia/Kuala_Lumpur")
        }
        let state = RepositorySnapshot(cities: cities, forecasts: Dictionary(uniqueKeysWithValues: cities.map {
            ($0.id, CityForecast(fetchedAt: date.addingTimeInterval(overdue ? -90000 : -1800), samples: unavailable ? [] : [.init(time: date, value: values[$0.id])]))
        }))
        let persistence = MemoryPersistence()
        try! persistence.save(state)
        let repository = try! ForecastRepository(provider: PreviewProvider(), searchProvider: PreviewProvider(), persistence: persistence, clock: FixedClock(now: date))
        let store = AppStore(repository: repository, clock: FixedClock(now: date), fixture: state, fixtureRefreshing: loading)
        if error { store.errorMessage = "You appear to be offline. Cached forecasts are still available." }
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
#Preview("City search") { CitySearchView(store: PreviewFixtures.store(empty: true)).frame(width: 360) }
#Preview("Settings") { SettingsContent() }
#Preview("City row") { CityRowView(status: PreviewFixtures.store().rows[0]).frame(width: 360) }
#endif
