import Foundation

struct StationObservation: Codable, Sendable {
    struct Index: Codable, Sendable { let value: Double; let scale: String; let metric: String }
    struct Station: Codable, Sendable {
        let id: String; let name: String; let latitude: Double; let longitude: Double; let distanceKm: Double
    }
    struct Concentration: Codable, Sendable { let value: Double; let unit: String; let averagingPeriod: String }
    struct Attribution: Codable, Sendable { let name: String; let url: URL }
    let source: String
    let index: Index
    let pm25Index: Index?
    let pm2524hConcentration: Concentration?
    let station: Station
    let observedAt: Date
    let fetchedAt: Date
    let attribution: [Attribution]
    enum CodingKeys: String, CodingKey {
        case source, index, station, attribution
        case pm25Index = "pm25_index", pm2524hConcentration = "pm25_24h_concentration"
        case observedAt = "observed_at", fetchedAt = "fetched_at"
    }
    var sourceLabel: String { source == "doe" ? "DOE Malaysia" : "AQICN" }
    func reading(at now: Date) -> AQIReading? {
        guard now.timeIntervalSince(observedAt) <= 7200, observedAt.timeIntervalSince(now) <= 300,
              let pm25Index else { return nil }
        return AQIReading(pm25Index.value, scale: pm25Index.scale)
    }
}

struct BackendProvider: AirQualityProvider {
    var cacheMetric: String { "station_pm25_v1" }
    let baseURL: URL?
    let transport: any HTTPFetching
    let clock: any AppClock
    init(baseURL: URL?, transport: any HTTPFetching = HTTPTransport(), clock: any AppClock = SystemClock()) {
        self.baseURL = baseURL; self.transport = transport; self.clock = clock
    }
    func forecast(for city: SavedCity) async throws -> CityForecast {
        guard let baseURL else { throw BackendError.configuration }
        guard let country = city.resolvedCountryCode else { throw BackendError.country }
        var components = URLComponents(url: baseURL.appendingPathComponent("v1/air-quality"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "lat", value: String(city.latitude)), URLQueryItem(name: "lon", value: String(city.longitude)), URLQueryItem(name: "country", value: country), URLQueryItem(name: "metric", value: "pm25")]
        let (data, response) = try await transport.get(components.url!)
        if response.statusCode == 422 { throw BackendError.unsupportedCountry }
        guard (200..<300).contains(response.statusCode) else {
            throw ProviderError.http(response.statusCode, retryAfter: OpenMeteoProvider.retryDelay(response.value(forHTTPHeaderField: "Retry-After"), now: clock.now))
        }
        return try Self.decode(data, now: clock.now)
    }
    static func decode(_ data: Data, now: Date) throws -> CityForecast {
        struct Envelope: Decodable {
            let schema_version: Int
            let observation: StationObservation
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: text) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            guard let date = formatter.date(from: text) else { throw BackendError.invalidObservation }
            return date
        }
        let envelope = try decoder.decode(Envelope.self, from: data)
        let o = envelope.observation
        let scale = o.source == "doe" ? "MY_API" : "AQICN_AQI"
        guard envelope.schema_version == 1, ["doe", "aqicn"].contains(o.source),
              o.index.scale == scale, o.index.metric == "overall", AQIReading(o.index.value) != nil,
              o.pm25Index == nil || (o.pm25Index?.scale == scale && o.pm25Index?.metric == "pm25" && AQIReading(o.pm25Index?.value) != nil),
              (-90...90).contains(o.station.latitude), (-180...180).contains(o.station.longitude),
              o.station.distanceKm.isFinite, o.station.distanceKm >= 0,
              !o.station.name.isEmpty, !o.attribution.isEmpty,
              o.attribution.allSatisfy({ ["https", "http"].contains($0.url.scheme) }),
              now.timeIntervalSince(o.observedAt) <= 7200, o.observedAt.timeIntervalSince(now) <= 300 else { throw BackendError.invalidObservation }
        if let concentration = o.pm2524hConcentration {
            guard o.source == "doe", concentration.value.isFinite, concentration.value >= 0,
                  concentration.unit == "µg/m³", concentration.averagingPeriod == "24h" else { throw BackendError.invalidObservation }
        }
        return CityForecast(fetchedAt: now, samples: [], metric: "station_pm25_v1", observation: o)
    }
    static func configuredURL(_ text: String?, development: Bool) -> URL? {
        guard let text, let url = URL(string: text), let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil else { return nil }
        if url.scheme == "https", !["localhost", "127.0.0.1", "::1"].contains(host) { return url }
        if development, url.scheme == "http", ["localhost", "127.0.0.1", "::1"].contains(host) { return url }
        return nil
    }
}
// Explicit nested keys preserve the public API's snake_case without mangling pm25 names.
extension StationObservation.Station {
    enum CodingKeys: String, CodingKey { case id, name, latitude, longitude; case distanceKm = "distance_km" }
}
extension StationObservation.Concentration {
    enum CodingKeys: String, CodingKey { case value, unit; case averagingPeriod = "averaging_period" }
}
enum BackendError: Error, LocalizedError {
    case configuration, country, invalidObservation, unsupportedCountry
    var errorDescription: String? {
        switch self {
        case .unsupportedCountry: "No provider supports this location."
        case .configuration: "Configure the Udara API URL, then rebuild the app."
        case .country: "Country is unknown. Remove and add this city again, or detect your location again."
        case .invalidObservation: "No valid recent station observation is available."
        }
    }
}
