import Foundation

struct SavedCity: Codable, Identifiable, Hashable, Sendable {
    let id: Int
    let name: String
    let region: String
    let country: String
    let latitude: Double
    let longitude: Double
    let timezone: String
    var countryCode: String? = nil
    var resolvedCountryCode: String? {
        if let countryCode, countryCode.count == 2 { return countryCode.uppercased() }
        let locale = Locale(identifier: "en_US")
        return Locale.Region.isoRegions.map(\.identifier).first { locale.localizedString(forRegionCode: $0) == country }
    }
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
    var scale: String = "US_AQI"
    var scaleLabel: String { scale == "MY_API" ? "Malaysian API" : "Estimated US AQI" }
    init?(_ raw: Double?, scale: String = "US_AQI") {
        self.scale = scale
        guard let raw, raw.isFinite, raw >= 0, raw.rounded() < Double(Int.max) else { return nil }
        value = Int(raw.rounded())
    }
    var category: AQICategory {
        if scale == "MY_API", (101...200).contains(value) { return .unhealthy }
        return switch value {
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
    var pm25Concentration: Double? = nil
}
enum ForecastRefreshPolicy {
    static let interval: TimeInterval = 3600
    static let maximumJitter: TimeInterval = 60
}

struct CityForecast: Codable, Sendable {
    let fetchedAt: Date
    let samples: [HourlyAQISample]
    // Optional for decoding old caches; absent/other metrics must never be relabeled as PM2.5.
    var metric: String? = "us_aqi_pm2_5"
    var observation: StationObservation? = nil
    var refreshInterval: TimeInterval { observation == nil ? ForecastRefreshPolicy.interval : 600 }
    func sample(at date: Date) -> HourlyAQISample? {
        guard metric == "us_aqi_pm2_5" else { return nil }
        let hour = floor(date.timeIntervalSince1970 / 3600) * 3600
        return samples.first { $0.time.timeIntervalSince1970 == hour }
    }
    func reading(at date: Date) -> AQIReading? {
        if metric == "station_pm25_v1", let observation { return observation.reading(at: date) }
        return sample(at: date).flatMap { AQIReading($0.value) }
    }
    func isOverdue(at date: Date) -> Bool {
        date < fetchedAt || date.timeIntervalSince(fetchedAt) >= refreshInterval
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
            if let a = $0.reading, let b = $1.reading, a.scale != b.scale { return a.scale < b.scale }
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
protocol AirQualityProvider: Sendable {
    var cacheMetric: String { get }
    func forecast(for city: SavedCity) async throws -> CityForecast
}
extension AirQualityProvider { var cacheMetric: String { "us_aqi_pm2_5" } }

/// The current location has a reserved identity outside geocoding's city IDs.
enum LocationPhase: Equatable, Sendable {
    case notRequested, locating, located, denied, unavailable
}


enum MenuBarIconStyle: String, Codable, CaseIterable, Sendable {
    case udara, dynamic
    var title: String { self == .udara ? "Udara icon" : "Dynamic AQI icon" }
    func symbol(for category: AQICategory?) -> String {
        self == .dynamic ? category?.symbol ?? "wind" : "wind"
    }
}
