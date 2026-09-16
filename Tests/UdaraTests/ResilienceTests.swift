import Foundation
import Testing
@testable import Udara

struct ResilienceTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    @Test func expiredCacheRefreshesButScheduledJitterWaits() async throws {
        let provider = CountingProvider(now: now)
        let persistence = MemoryPersistence()
        let forecast = CityForecast(fetchedAt: now.addingTimeInterval(-86400), samples: [])
        try persistence.save(.init(cities: [city()], forecasts: [1: forecast], scheduled: [1: now.addingTimeInterval(300)]))
        let waiting = try ForecastRepository(provider: provider, persistence: persistence, clock: FixedClock(now: now))
        _ = await waiting.refreshDue()
        #expect(await provider.calls == 0)
        let due = try ForecastRepository(provider: provider, persistence: persistence, clock: FixedClock(now: now.addingTimeInterval(300)))
        _ = await due.refreshDue()
        #expect(await provider.calls == 1)
    }
    @Test func removedCityDoesNotReturnAfterInflightRequest() async throws {
        let provider = CountingProvider(now: now)
        let repository = try ForecastRepository(provider: provider, persistence: MemoryPersistence(), clock: FixedClock(now: now))
        try await repository.add(city())
        let refresh = Task { await repository.refreshDue() }
        while await provider.calls == 0 { await Task.yield() }
        try await repository.remove(1)
        _ = await refresh.value
        let state = await repository.snapshot()
        #expect(state.cities.isEmpty)
        #expect(state.forecasts.isEmpty)
        #expect(state.retries.isEmpty)
    }
    @Test func diskRoundtripAndCorruptDataIsNotOverwritten() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let disk = DiskPersistence(directory: directory)
        try disk.save(.init(cities: [city()]))
        #expect(try disk.load()?.cities == [city()])
        let corrupt = Data("not-json".utf8)
        try corrupt.write(to: disk.file)
        #expect(throws: (any Error).self) { try disk.load() }
        #expect(try Data(contentsOf: disk.file) == corrupt)
    }
    @Test func futureSchemaIsPreserved() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let disk = DiskPersistence(directory: directory)
        var state = RepositorySnapshot(); state.version = 99
        try disk.save(state)
        #expect(throws: PersistenceError.self) { try disk.load() }
        #expect(try JSONDecoder().decode(RepositorySnapshot.self, from: Data(contentsOf: disk.file)).version == 99)
    }
    @Test func normalizedSearchIsCachedAndShortQueriesAreIgnored() async throws {
        let search = CountingSearch()
        let repository = try ForecastRepository(provider: FailingProvider(), searchProvider: search, persistence: MemoryPersistence(), clock: FixedClock(now: now))
        #expect(try await repository.search("ab").isEmpty)
        #expect(try await repository.search("  Kuala  ").count == 1)
        #expect(try await repository.search("kuala").count == 1)
        #expect(await search.calls == 1)
    }
    @Test func utcSelectionIsIndependentOfDSTAndLongSleep() {
        let hour = Date(timeIntervalSince1970: 1_793_512_800)
        let forecast = CityForecast(fetchedAt: hour, samples: [.init(time: hour, value: 90), .init(time: hour.addingTimeInterval(3600), value: 140)])
        #expect(forecast.reading(at: hour.addingTimeInterval(3599))?.value == 90)
        #expect(forecast.reading(at: hour.addingTimeInterval(3600))?.value == 140)
        #expect(forecast.reading(at: hour.addingTimeInterval(3 * 86400)) == nil)
    }
    @Test func providerBuildsKeylessRequestAndHandles429() async throws {
        let transport = StubTransport(status: 429, headers: ["Retry-After": "120"])
        let provider = OpenMeteoProvider(transport: transport, clock: FixedClock(now: now))
        do { _ = try await provider.forecast(for: city()); Issue.record("Expected 429") }
        catch ProviderError.http(let code, let delay) { #expect(code == 429); #expect(delay == 120) }
        let url = try #require(await transport.url)
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(url.host == "air-quality-api.open-meteo.com")
        #expect(query.contains(.init(name: "forecast_days", value: "3")))
        #expect(query.contains(.init(name: "timezone", value: "GMT")))
        #expect(!query.contains { $0.name == "apikey" })
    }
    @Test func httpDateRetryAfter() {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = .gmt
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        #expect(OpenMeteoProvider.retryDelay(formatter.string(from: now.addingTimeInterval(90)), now: now) == 90)
    }
}
actor CountingSearch: CitySearchProvider {
    var calls = 0
    func search(_ query: String) async throws -> [SavedCity] { calls += 1; return [city()] }
}
actor StubTransport: HTTPFetching {
    let status: Int
    let headers: [String: String]
    var url: URL?
    init(status: Int, headers: [String: String] = [:]) { self.status = status; self.headers = headers }
    func get(_ url: URL) async throws -> (Data, HTTPURLResponse) {
        self.url = url
        return (Data(), HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: headers)!)
    }
}

struct FailureIsolationTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    @Test func partialFailureDoesNotDiscardOtherCity() async throws {
        let repository = try ForecastRepository(provider: MixedProvider(now: now), persistence: MemoryPersistence(), clock: FixedClock(now: now), jitter: { 0 })
        try await repository.add(city(1))
        try await repository.add(city(2))
        let state = await repository.refreshDue()
        #expect(state.forecasts[1]?.reading(at: now)?.value == 42)
        #expect(state.forecasts[2] == nil)
        #expect(state.retries[2]?.failures == 1)
        #expect(state.retries[2]?.nextAttempt == now.addingTimeInterval(60))
    }
    @Test func retryLadderAndRestartRetainCooldown() async throws {
        let clock = MutableClock(now)
        let persistence = MemoryPersistence()
        let repository = try ForecastRepository(provider: OfflineProvider(), persistence: persistence, clock: clock, jitter: { 0 })
        try await repository.add(city())
        for delay: TimeInterval in [60, 300, 900, 3600, 3600] {
            let current = clock.now
            let state = await repository.refreshDue()
            #expect(state.retries[1]?.nextAttempt == current.addingTimeInterval(delay))
            clock.advance(delay)
        }
    }
    @Test @MainActor func cancelledSearchDoesNotReplaceNewResults() async throws {
        let repository = try ForecastRepository(provider: OfflineProvider(), searchProvider: SlowSearch(), persistence: MemoryPersistence(), clock: FixedClock(now: now))
        let store = AppStore(repository: repository)
        let old = Task { await store.search("old") }
        try await Task.sleep(for: .milliseconds(420))
        old.cancel()
        await store.search("new")
        await old.value
        #expect(store.searchResults.first?.name == "new")
        #expect(store.searchError == nil)
    }
}
struct MixedProvider: AirQualityProvider {
    let now: Date
    func forecast(for city: SavedCity) async throws -> CityForecast {
        if city.id == 2 { throw URLError(.notConnectedToInternet) }
        return .init(fetchedAt: now, samples: [.init(time: now, value: 42)])
    }
}
struct OfflineProvider: AirQualityProvider {
    func forecast(for city: SavedCity) async throws -> CityForecast { throw URLError(.notConnectedToInternet) }
}
struct SlowSearch: CitySearchProvider {
    func search(_ query: String) async throws -> [SavedCity] {
        try await Task.sleep(for: .milliseconds(query == "old" ? 150 : 10))
        return [city(1, query)]
    }
}
final class MutableClock: AppClock, @unchecked Sendable {
    private let lock = NSLock()
    private var date: Date
    init(_ date: Date) { self.date = date }
    var now: Date { lock.withLock { date } }
    func advance(_ seconds: TimeInterval) { lock.withLock { date = date.addingTimeInterval(seconds) } }
}
