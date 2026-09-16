import Foundation
import Testing
@testable import Udara

struct DomainTests {
    @Test func categoryBoundariesAndInvalidValues() {
        let cases: [(Double, AQICategory)] = [(0, .good), (50.49, .good), (50.5, .moderate), (100, .moderate), (101, .sensitive), (150, .sensitive), (151, .unhealthy), (200, .unhealthy), (201, .veryUnhealthy), (300, .veryUnhealthy), (301, .hazardous), (900, .hazardous)]
        for (value, expected) in cases { #expect(AQICategory.classify(value) == expected) }
        for value in [-1.0, .infinity, .nan, Double.greatestFiniteMagnitude] { #expect(AQIReading(value) == nil) }
    }
    @Test func onlyExactCurrentUTCHourIsUsed() {
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        let forecast = CityForecast(fetchedAt: base, samples: [HourlyAQISample(time: base, value: 55)])
        #expect(forecast.reading(at: base.addingTimeInterval(3599))?.value == 55)
        #expect(forecast.reading(at: base.addingTimeInterval(3600)) == nil)
        #expect(forecast.reading(at: base.addingTimeInterval(-1)) == nil)
    }
    @Test func overdueAndClockRollbackAreExplicit() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let forecast = CityForecast(fetchedAt: now, samples: [])
        #expect(!forecast.isOverdue(at: now.addingTimeInterval(86399)))
        #expect(forecast.isOverdue(at: now.addingTimeInterval(86400)))
        #expect(forecast.isOverdue(at: now.addingTimeInterval(-3600)))
    }
    @Test func descendingOrderWithStableTiesAndMissingLast() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let cities = [city(3, "Zulu"), city(2, "Beta"), city(1, "Alpha"), city(4, "Missing")]
        let forecasts = Dictionary(uniqueKeysWithValues: cities.prefix(3).map { ($0.id, CityForecast(fetchedAt: now, samples: [.init(time: now, value: $0.id == 3 ? 200 : 50)])) })
        #expect(CityStatus.sorted(cities: cities, forecasts: forecasts, now: now).map(\.city.id) == [3, 1, 2, 4])
    }
}
func city(_ id: Int = 1, _ name: String = "Kuala Lumpur") -> SavedCity {
    SavedCity(id: id, name: name, region: "Region", country: "Malaysia", latitude: 3.139, longitude: 101.6869, timezone: "Asia/Kuala_Lumpur")
}
