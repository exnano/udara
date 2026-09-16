import Foundation
import Testing
@testable import Udara

@MainActor struct StoreTests {
    @Test func storeLoadsAndRemovesCities() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let repository = try ForecastRepository(provider: CountingProvider(now: now), persistence: MemoryPersistence(), clock: FixedClock(now: now))
        let store = AppStore(repository: repository, clock: FixedClock(now: now))
        await store.add(city())
        #expect(store.rows.count == 1)
        #expect(store.rows.first?.reading?.value == 42)
        await store.remove(city())
        #expect(store.rows.isEmpty)
    }
    @Test func shortSearchClearsResultsWithoutRequest() async throws {
        let repository = try ForecastRepository(provider: FailingProvider(), persistence: MemoryPersistence())
        let store = AppStore(repository: repository)
        store.searchResults = [city()]
        await store.search("ab")
        #expect(store.searchResults.isEmpty)
        #expect(!store.isSearching)
    }
}

@MainActor struct RefreshRaceTests {
    @Test func addingDuringRefreshStillFetchesNewCityImmediately() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let provider = CountingProvider(now: now)
        let repository = try ForecastRepository(provider: provider, persistence: MemoryPersistence(), clock: FixedClock(now: now))
        try await repository.add(city(1))
        let store = AppStore(repository: repository, clock: FixedClock(now: now))
        let first = Task { await store.refresh() }
        while await provider.calls == 0 { await Task.yield() }
        await store.add(city(2))
        await first.value
        #expect(store.state.forecasts[2] != nil)
    }
}

@MainActor struct CurrentLocationTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    func location(_ latitude: Double = 3.14) -> SavedCity {
        SavedCity(id: -1, name: "Nearby", region: "", country: "Malaysia", latitude: latitude, longitude: 101.69, timezone: "Asia/Kuala_Lumpur")
    }
    @Test func locationIsSeparateAndReusesFreshCache() async throws {
        let provider = CountingProvider(now: now)
        let repository = try ForecastRepository(provider: provider, persistence: MemoryPersistence(), clock: FixedClock(now: now))
        let store = AppStore(repository: repository, clock: FixedClock(now: now))
        await store.updateLocation(location())
        #expect(store.currentLocationRow?.reading?.value == 42)
        #expect(store.rows.isEmpty)
        await store.updateLocation(location())
        #expect(await provider.calls == 1)
        await store.updateLocation(location(4.0))
        #expect(await provider.calls == 2)
        await store.locationUnavailable(.denied)
        #expect(store.currentLocationRow == nil)
        #expect(store.state.currentLocation == nil)
        #expect(store.state.forecasts[-1] == nil)
    }
    @Test func restartWaitsForLocationBeforeDownloading() async throws {
        let persistence = MemoryPersistence()
        let provider = CountingProvider(now: now)
        let repository = try ForecastRepository(provider: provider, persistence: persistence, clock: FixedClock(now: now))
        try await repository.setCurrentLocation(location())
        _ = await repository.refreshDue()
        let restored = try ForecastRepository(provider: provider, persistence: persistence, clock: FixedClock(now: now.addingTimeInterval(7200)))
        _ = await restored.refreshDue()
        #expect(await provider.calls == 1)
        #expect(await restored.snapshot().currentLocation != nil)
    }
    @Test func temporaryFailurePreservesCacheAndRetrySurvivesMovement() async throws {
        let persistence = MemoryPersistence()
        let provider = CountingProvider(now: now)
        let repository = try ForecastRepository(provider: provider, persistence: persistence, clock: FixedClock(now: now))
        let store = AppStore(repository: repository, clock: FixedClock(now: now))
        await store.updateLocation(location())
        await store.locationUnavailable(.unavailable)
        #expect(store.currentLocationRow == nil)
        #expect(store.state.forecasts[-1] != nil)
        await store.updateLocation(location())
        #expect(await provider.calls == 1)
        let failing = try ForecastRepository(provider: FailingProvider(), persistence: MemoryPersistence(), clock: FixedClock(now: now), jitter: { 0 })
        try await failing.setCurrentLocation(location())
        _ = await failing.refreshDue()
        let deadline = await failing.snapshot().retries[-1]?.nextAttempt
        try await failing.setCurrentLocation(location(4))
        #expect(await failing.snapshot().retries[-1]?.nextAttempt == deadline)
    }
    @Test func revokedLocationCannotReturnFromInflightRequest() async throws {
        let provider = CountingProvider(now: now)
        let repository = try ForecastRepository(provider: provider, persistence: MemoryPersistence(), clock: FixedClock(now: now))
        try await repository.setCurrentLocation(location())
        let pending = Task { await repository.refreshDue() }
        while await provider.calls == 0 { await Task.yield() }
        try await repository.setCurrentLocation(nil)
        _ = await pending.value
        #expect(await repository.snapshot().currentLocation == nil)
        #expect(await repository.snapshot().forecasts[-1] == nil)
    }
    @Test func oldSnapshotWithoutLocationStillDecodes() throws {
        let data = try JSONEncoder().encode(RepositorySnapshot())
        var json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json.removeValue(forKey: "currentLocation")
        let restored = try JSONDecoder().decode(RepositorySnapshot.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(restored.currentLocation == nil)
    }
}

@MainActor struct MenuBarPreferenceTests {
    @Test func iconPreferencePersistsAndOldSnapshotsUseUdara() async throws {
        let persistence = MemoryPersistence()
        let repository = try ForecastRepository(provider: FailingProvider(), persistence: persistence)
        let store = AppStore(repository: repository)
        await store.load()
        #expect(store.menuBarIconStyle == .udara)
        await store.setMenuBarIconStyle(.dynamic)
        let restored = try ForecastRepository(provider: FailingProvider(), persistence: persistence)
        #expect(await restored.snapshot().menuBarIconStyle == .dynamic)
        let json = Data(#"{"version":1,"cities":[],"forecasts":{},"scheduled":{},"retries":{},"searches":{}}"#.utf8)
        let legacy = try JSONDecoder().decode(RepositorySnapshot.self, from: json)
        #expect(legacy.menuBarIconStyle == nil)
    }
    @Test func iconModesAndUnavailableValue() {
        for category in AQICategory.allCases {
            #expect(MenuBarIconStyle.dynamic.symbol(for: category) == category.symbol)
            #expect(MenuBarIconStyle.udara.symbol(for: category) == "wind")
        }
        #expect(MenuBarIconStyle.dynamic.symbol(for: nil) == "wind")
    }
}
