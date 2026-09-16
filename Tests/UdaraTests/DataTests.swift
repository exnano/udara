import Foundation
import Testing
@testable import Udara

struct DataTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    @Test func decoderRejectsMismatchedOrMissingCoverage() throws {
        let bad = Data(#"{"hourly":{"time":[1800000000],"us_aqi_pm2_5":[]}}"#.utf8)
        #expect(throws: (any Error).self) { try OpenMeteoProvider.decodeForecast(bad, fetchedAt: now) }
        let short = Data(#"{"hourly":{"time":[1800000000],"us_aqi_pm2_5":[55]}}"#.utf8)
        #expect(throws: (any Error).self) { try OpenMeteoProvider.decodeForecast(short, fetchedAt: now) }
    }
    @Test func decodingPreservesNullAndIgnoresAdditionalFields() throws {
        let times = (0..<48).map { 1_800_000_000 + $0 * 3600 }
        let payload: [String: Any] = ["extra": 1, "hourly": ["time": times, "us_aqi_pm2_5": [NSNull()] + Array(repeating: 44, count: 47)]]
        let forecast = try OpenMeteoProvider.decodeForecast(JSONSerialization.data(withJSONObject: payload), fetchedAt: now)
        #expect(forecast.reading(at: now) == nil)
        #expect(forecast.reading(at: now.addingTimeInterval(3600))?.value == 44)
    }
    @Test func freshCacheAndConcurrentRefreshUseOneCall() async throws {
        let provider = CountingProvider(now: now)
        let repository = try ForecastRepository(provider: provider, persistence: MemoryPersistence(), clock: FixedClock(now: now), jitter: { 0 })
        try await repository.add(city())
        async let first = repository.refreshDue()
        async let second = repository.refreshDue()
        _ = await (first, second)
        for _ in 0..<10 { _ = await repository.refreshDue() }
        #expect(await provider.calls == 1)
        #expect(await repository.snapshot().forecasts[1]?.reading(at: now)?.value == 42)
    }
    @Test func retryIsPersistedAndOldForecastSurvives() async throws {
        let persistence = MemoryPersistence()
        let old = CityForecast(fetchedAt: now.addingTimeInterval(-86400), samples: [.init(time: now, value: 77)])
        try persistence.save(RepositorySnapshot(cities: [city()], forecasts: [1: old]))
        let repository = try ForecastRepository(provider: FailingProvider(), persistence: persistence, clock: FixedClock(now: now), jitter: { 0 })
        let result = await repository.refreshDue()
        #expect(result.forecasts[1]?.reading(at: now)?.value == 77)
        #expect(result.retries[1]?.nextAttempt == now.addingTimeInterval(120))
        let restored = try ForecastRepository(provider: FailingProvider(), persistence: persistence, clock: FixedClock(now: now), jitter: { 0 })
        #expect(await restored.snapshot().retries[1]?.nextAttempt == now.addingTimeInterval(120))
    }
    @Test func duplicateCitiesAndRemovalPersist() async throws {
        let persistence = MemoryPersistence()
        let repository = try ForecastRepository(provider: CountingProvider(now: now), persistence: persistence, clock: FixedClock(now: now))
        try await repository.add(city())
        try await repository.add(city())
        try await repository.add(city(2, "Kuala Lumpur"))
        #expect(await repository.snapshot().cities.count == 2)
        try await repository.remove(1)
        #expect(try persistence.load()?.cities.map(\.id) == [2])
    }
    @Test func retryAfterSupportsHTTPDate() {
        #expect(OpenMeteoProvider.retryDelay("120", now: now) == 120)
        #expect(OpenMeteoProvider.retryDelay("garbage", now: now) == nil)
    }
}
actor CountingProvider: AirQualityProvider {
    var calls = 0
    let now: Date
    init(now: Date) { self.now = now }
    func forecast(for city: SavedCity) async throws -> CityForecast {
        calls += 1
        try await Task.sleep(for: .milliseconds(30))
        return .init(fetchedAt: now, samples: [.init(time: now, value: 42)])
    }
}
struct FailingProvider: AirQualityProvider {
    func forecast(for city: SavedCity) async throws -> CityForecast { throw ProviderError.http(429, retryAfter: 120) }
}

struct PM25MigrationTests {
    @Test func overallAQICannotBeRelabeledAsPM25() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let legacyJSON = Data(#"{"fetchedAt":821692800,"samples":[{"time":821692800,"value":202}]}"#.utf8)
        let legacy = try JSONDecoder().decode(CityForecast.self, from: legacyJSON)
        #expect(legacy.reading(at: now) == nil)
        let persistence = MemoryPersistence()
        let retry = RetryState(failures: 1, nextAttempt: now.addingTimeInterval(120), message: "Wait")
        try persistence.save(RepositorySnapshot(cities: [city()], forecasts: [1: legacy], scheduled: [1: now.addingTimeInterval(3600)], retries: [1: retry], menuBarIconStyle: .dynamic))
        let repository = try ForecastRepository(provider: FailingProvider(), persistence: persistence, clock: FixedClock(now: now))
        let state = await repository.snapshot()
        #expect(state.cities.count == 1)
        #expect(state.forecasts.isEmpty)
        #expect(state.scheduled.isEmpty)
        #expect(state.retries[1]?.nextAttempt == retry.nextAttempt)
        #expect(state.menuBarIconStyle == .dynamic)
    }
    @Test func decodesPM25InsteadOfOverallAndConcentrationIsSeparate() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let payload: [String: Any] = ["hourly": ["time": [1800000000,1800003600,1800007200], "us_aqi": [202,202,202], "us_aqi_pm2_5": [185,184,183], "pm2_5": [67.1,60.0,55.0]]]
        let forecast = try OpenMeteoProvider.decodeForecast(JSONSerialization.data(withJSONObject: payload), fetchedAt: now)
        #expect(forecast.reading(at: now)?.value == 185)
        #expect(forecast.sample(at: now)?.pm25Concentration == 67.1)
    }
}

struct PM25PayloadTests {
    @Test func refusesOverallOnlyAndMismatchedConcentrations() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        for hourly: [String: Any] in [
            ["time": [1800000000,1800003600,1800007200], "us_aqi": [202,202,202]],
            ["time": [1800000000,1800003600,1800007200], "us_aqi_pm2_5": [185,184,183], "pm2_5": [67.1]],
        ] {
            let data = try JSONSerialization.data(withJSONObject: ["hourly": hourly])
            #expect(throws: (any Error).self) { try OpenMeteoProvider.decodeForecast(data, fetchedAt: now) }
        }
    }
    @Test func newCacheKeepsMetricAndInvalidConcentrationIsUnavailable() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let payload: [String: Any] = ["hourly": ["time": [1800000000,1800003600,1800007200], "us_aqi_pm2_5": [185,184,183], "pm2_5": [-1,NSNull(),0]]]
        let forecast = try OpenMeteoProvider.decodeForecast(JSONSerialization.data(withJSONObject: payload), fetchedAt: now)
        let restored = try JSONDecoder().decode(CityForecast.self, from: JSONEncoder().encode(forecast))
        #expect(restored.metric == "us_aqi_pm2_5")
        #expect(restored.reading(at: now)?.value == 185)
        #expect(restored.sample(at: now)?.pm25Concentration == nil)
        #expect(restored.sample(at: now.addingTimeInterval(7200))?.pm25Concentration == 0)
    }
}
