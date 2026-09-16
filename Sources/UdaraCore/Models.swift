import Foundation

struct SavedCity: Codable, Identifiable, Hashable, Sendable {
    let id: Int
    let name: String
    let region: String
    let country: String
    let latitude: Double
    let longitude: Double
    let timezone: String
    var subtitle: String { [region, country].filter { !$0.isEmpty }.joined(separator: ", ") }
}

enum AQICategory: String, Codable, CaseIterable, Sendable {
    case good, moderate, sensitive, unhealthy, veryUnhealthy, hazardous
    static func classify(_ value: Double) -> Self? { AQIReading(value)?.category }
    var title: String {
        switch self {
        case .good: "Good"
        case .moderate: "Moderate"
        case .sensitive: "Unhealthy for sensitive groups"
        case .unhealthy: "Unhealthy"
        case .veryUnhealthy: "Very unhealthy"
        case .hazardous: "Hazardous"
        }
    }
    var symbol: String {
        switch self {
        case .good: "leaf.fill"
        case .moderate: "circle.lefthalf.filled"
        case .sensitive: "exclamationmark.circle.fill"
        case .unhealthy: "exclamationmark.triangle.fill"
        case .veryUnhealthy: "exclamationmark.octagon.fill"
        case .hazardous: "xmark.octagon.fill"
        }
    }
}
struct AQIReading: Equatable, Sendable {
    let value: Int
    init?(_ raw: Double?) {
        guard let raw, raw.isFinite, raw >= 0, raw.rounded() < Double(Int.max) else { return nil }
        value = Int(raw.rounded())
    }
    var category: AQICategory {
        switch value {
        case ...50: .good
        case ...100: .moderate
        case ...150: .sensitive
        case ...200: .unhealthy
        case ...300: .veryUnhealthy
        default: .hazardous
        }
    }
}
struct HourlyAQISample: Codable, Sendable {
    let time: Date
    let value: Double?
}
struct CityForecast: Codable, Sendable {
    let fetchedAt: Date
    let samples: [HourlyAQISample]
    func reading(at date: Date) -> AQIReading? {
        let hour = floor(date.timeIntervalSince1970 / 3600) * 3600
        return samples.first { $0.time.timeIntervalSince1970 == hour }.flatMap { AQIReading($0.value) }
    }
    func isOverdue(at date: Date) -> Bool {
        date < fetchedAt || date.timeIntervalSince(fetchedAt) >= 86400
    }
}
struct CityStatus: Identifiable, Sendable {
    let city: SavedCity
    let forecast: CityForecast?
    let now: Date
    var id: Int { city.id }
    var reading: AQIReading? { forecast?.reading(at: now) }
    var overdue: Bool { forecast?.isOverdue(at: now) ?? false }
    static func sorted(cities: [SavedCity], forecasts: [Int: CityForecast], now: Date) -> [Self] {
        cities.map { Self(city: $0, forecast: forecasts[$0.id], now: now) }.sorted {
            let left = $0.reading?.value ?? -1, right = $1.reading?.value ?? -1
            if left != right { return left > right }
            if $0.city.name != $1.city.name { return $0.city.name < $1.city.name }
            if $0.city.country != $1.city.country { return $0.city.country < $1.city.country }
            return $0.id < $1.id
        }
    }
}
protocol AppClock: Sendable { var now: Date { get } }
struct SystemClock: AppClock { var now: Date { Date() } }
struct FixedClock: AppClock { let now: Date }
protocol CitySearchProvider: Sendable { func search(_ query: String) async throws -> [SavedCity] }
protocol AirQualityProvider: Sendable { func forecast(for city: SavedCity) async throws -> CityForecast }
