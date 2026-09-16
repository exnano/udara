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
