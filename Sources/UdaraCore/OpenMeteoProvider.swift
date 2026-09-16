import Foundation

enum ProviderError: Error, LocalizedError, Sendable {
    case invalidResponse
    case http(Int, retryAfter: TimeInterval?)
    var errorDescription: String? {
        switch self {
        case .invalidResponse: "The provider returned incomplete forecast data."
        case .http(429, _): "The provider is busy. Udara will retry later."
        case .http(let code, _): "The provider returned HTTP \(code)."
        }
    }
}
protocol HTTPFetching: Sendable { func get(_ url: URL) async throws -> (Data, HTTPURLResponse) }
/// Shared by search and forecasts: at most two HTTP requests are active.
actor HTTPTransport: HTTPFetching {
    private let session: URLSession
    private var active = 0
    private var waiting: [CheckedContinuation<Void, Never>] = []
    init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 45
        session = URLSession(configuration: config)
    }
    func get(_ url: URL) async throws -> (Data, HTTPURLResponse) {
        if active >= 2 { await withCheckedContinuation { waiting.append($0) } }
        else { active += 1 }
        defer {
            if waiting.isEmpty { active -= 1 } else { waiting.removeFirst().resume() }
        }
        try Task.checkCancellation()
        var request = URLRequest(url: url)
        request.setValue("Udara/1.0 (macOS air quality app)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw ProviderError.invalidResponse }
        return (data, response)
    }
}
struct OpenMeteoProvider: CitySearchProvider, AirQualityProvider {
    let transport: any HTTPFetching
    let clock: any AppClock
    init(transport: any HTTPFetching = HTTPTransport(), clock: any AppClock = SystemClock()) {
        self.transport = transport; self.clock = clock
    }
    func forecast(for city: SavedCity) async throws -> CityForecast {
        let data = try await request(host: "air-quality-api.open-meteo.com", path: "/v1/air-quality", items: [
            "latitude": String(city.latitude), "longitude": String(city.longitude), "hourly": "us_aqi_pm2_5,pm2_5",
            "forecast_days": "3", "timezone": "GMT", "timeformat": "unixtime"
        ])
        return try Self.decodeForecast(data, fetchedAt: clock.now)
    }
    static func decodeForecast(_ data: Data, fetchedAt: Date) throws -> CityForecast {
        struct Response: Decodable {
            struct Hourly: Decodable { let time: [Double]; let us_aqi_pm2_5: [Double?]; let pm2_5: [Double?]? }
            let hourly: Hourly
        }
        let hourly = try JSONDecoder().decode(Response.self, from: data).hourly
        guard hourly.time.count == hourly.us_aqi_pm2_5.count, !hourly.time.isEmpty,
              hourly.pm2_5 == nil || hourly.pm2_5?.count == hourly.time.count,
              hourly.time.allSatisfy({ $0.isFinite && $0.truncatingRemainder(dividingBy: 3600) == 0 }),
              zip(hourly.time, hourly.time.dropFirst()).allSatisfy({ $1 - $0 == 3600 })
        else { throw ProviderError.invalidResponse }
        let currentHour = floor(fetchedAt.timeIntervalSince1970 / 3600) * 3600
        // Enough coverage for the next hourly refresh, including scheduling jitter.
        guard hourly.time.first! <= currentHour, hourly.time.last! >= currentHour + 2 * 3600 else {
            throw ProviderError.invalidResponse
        }
        return CityForecast(fetchedAt: fetchedAt, samples: hourly.time.indices.map { index in
            let concentration = hourly.pm2_5?[index]
            let validConcentration = concentration.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
            return HourlyAQISample(time: Date(timeIntervalSince1970: hourly.time[index]), value: hourly.us_aqi_pm2_5[index], pm25Concentration: validConcentration)
        })
    }
    func search(_ query: String) async throws -> [SavedCity] {
        guard query.trimmingCharacters(in: .whitespacesAndNewlines).count >= 3 else { return [] }
        let data = try await request(host: "geocoding-api.open-meteo.com", path: "/v1/search", items: ["name": query, "count": "10", "language": "en", "format": "json"])
        struct Response: Decodable {
            struct City: Decodable {
                let id: Int; let name: String; let latitude: Double; let longitude: Double
                let admin1: String?; let country: String?; let timezone: String?
            }
            let results: [City]?
        }
        return try JSONDecoder().decode(Response.self, from: data).results?.compactMap {
            guard (-90...90).contains($0.latitude), (-180...180).contains($0.longitude) else { return nil }
            return SavedCity(id: $0.id, name: $0.name, region: $0.admin1 ?? "", country: $0.country ?? "", latitude: $0.latitude, longitude: $0.longitude, timezone: $0.timezone ?? "GMT")
        } ?? []
    }
    private func request(host: String, path: String, items: [String: String]) async throws -> Data {
        var components = URLComponents()
        components.scheme = "https"; components.host = host; components.path = path
        components.queryItems = items.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let url = components.url else { throw ProviderError.invalidResponse }
        let (data, response) = try await transport.get(url)
        guard (200..<300).contains(response.statusCode) else {
            throw ProviderError.http(response.statusCode, retryAfter: Self.retryDelay(response.value(forHTTPHeaderField: "Retry-After"), now: clock.now))
        }
        return data
    }
    static func retryDelay(_ value: String?, now: Date) -> TimeInterval? {
        guard let value else { return nil }
        if let seconds = Double(value), seconds.isFinite { return max(0, seconds) }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter.date(from: value).map { max(0, $0.timeIntervalSince(now)) }
    }
}
