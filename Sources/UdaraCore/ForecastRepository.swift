import Foundation

actor ForecastRepository {
    private let provider: any AirQualityProvider
    private let searchProvider: (any CitySearchProvider)?
    private let persistence: any SnapshotPersistence
    private let clock: any AppClock
    private let jitter: @Sendable () -> TimeInterval
    private var state: RepositorySnapshot
    private var inFlight: [Int: Task<CityForecast, any Error>] = [:]
    private var locationEnabled = false
    private var generations: [Int: UUID] = [:]
    private(set) var persistenceWarning: String?

    init(provider: any AirQualityProvider, searchProvider: (any CitySearchProvider)? = nil,
         persistence: any SnapshotPersistence, clock: any AppClock = SystemClock(),
         jitter: @escaping @Sendable () -> TimeInterval = { Double.random(in: 0...ForecastRefreshPolicy.maximumJitter) }) throws {
        self.provider = provider; self.searchProvider = searchProvider; self.persistence = persistence
        self.clock = clock; self.jitter = jitter
        state = try persistence.load() ?? RepositorySnapshot()
        let incompatible = state.forecasts.filter { $0.value.metric != "us_aqi_pm2_5" }.map(\.key)
        for id in incompatible {
            state.forecasts[id] = nil
            state.scheduled[id] = nil
        }
        // Normalize legacy daily deadlines without clearing forecasts, cities or server cooldowns.
        for (id, forecast) in state.forecasts {
            let earliest = forecast.fetchedAt.addingTimeInterval(ForecastRefreshPolicy.interval)
            let latest = earliest.addingTimeInterval(ForecastRefreshPolicy.maximumJitter)
            state.scheduled[id] = min(latest, max(earliest, state.scheduled[id] ?? earliest))
        }
    }
    func snapshot() -> RepositorySnapshot { state }
    func setMenuBarIconStyle(_ style: MenuBarIconStyle) throws {
        var next = state
        next.menuBarIconStyle = style
        try persistence.save(next)
        state = next
    }
    private var activeCities: [SavedCity] {
        state.cities + (locationEnabled ? state.currentLocation.map { [$0] } ?? [] : [])
    }
    func suspendCurrentLocation() {
        locationEnabled = false
        generations[-1] = UUID()
        inFlight.removeValue(forKey: -1)?.cancel()
    }
    func setCurrentLocation(_ city: SavedCity?) throws {
        precondition(city == nil || city?.id == -1)
        let old = state.currentLocation
        let moved = old?.latitude != city?.latitude || old?.longitude != city?.longitude
        var next = state
        next.currentLocation = city
        if moved || city == nil {
            next.forecasts[-1] = nil
            next.scheduled[-1] = nil
            // Keep server cooldowns when moving; clear private data on revocation.
            if city == nil { next.retries[-1] = nil }
        }
        if city == nil {
            suspendCurrentLocation()
            state = next
            try persistence.save(next)
            return
        }
        try persistence.save(next)
        state = next
        locationEnabled = true
        if moved || city == nil {
            generations[-1] = UUID()
            inFlight.removeValue(forKey: -1)?.cancel()
        }
    }

    func add(_ city: SavedCity) throws {
        guard !state.cities.contains(where: { $0.id == city.id }) else { return }
        var next = state; next.cities.append(city)
        try persistence.save(next); state = next
        generations[city.id] = UUID()
    }
    func remove(_ id: Int) throws {
        var next = state
        next.cities.removeAll { $0.id == id }
        next.forecasts[id] = nil; next.retries[id] = nil; next.scheduled[id] = nil
        try persistence.save(next); state = next
        generations[id] = UUID()
        inFlight.removeValue(forKey: id)?.cancel()
    }
    func refreshDue() async -> RepositorySnapshot {
        let cities = activeCities
        await withTaskGroup(of: Void.self) { group in
            for city in cities { group.addTask { await self.refresh(city) } }
        }
        return state
    }
    private func refresh(_ city: SavedCity) async {
        guard activeCities.contains(where: { $0.id == city.id }) else { return }
        if let task = inFlight[city.id] { _ = try? await task.value; return }
        let now = clock.now
        if let retry = state.retries[city.id], retry.nextAttempt > now { return }
        if let forecast = state.forecasts[city.id] {
            // On clock rollback, wait for the original deadline rather than causing a request burst.
            let deadline = state.scheduled[city.id] ?? forecast.fetchedAt.addingTimeInterval(ForecastRefreshPolicy.interval)
            if deadline > now { return }
        }
        let generation = generations[city.id] ?? UUID()
        generations[city.id] = generation
        let task = Task { try await provider.forecast(for: city) }
        inFlight[city.id] = task
        let result = await task.result
        guard generations[city.id] == generation else { return }
        inFlight[city.id] = nil
        guard activeCities.contains(where: { $0.id == city.id }) else { return }
        switch result {
        case .success(let forecast):
            state.forecasts[city.id] = forecast
            state.scheduled[city.id] = forecast.fetchedAt.addingTimeInterval(ForecastRefreshPolicy.interval + boundedJitter())
            state.retries[city.id] = nil
        case .failure(let error):
            guard !(error is CancellationError) else { return }
            state.retries[city.id] = retryState(error, previous: state.retries[city.id])
        }
        persist()
    }
    func search(_ query: String) async throws -> [SavedCity] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 3 else { return [] }
        let key = trimmed.lowercased()
        let now = clock.now
        if let cached = state.searches[key], now >= cached.fetchedAt, now.timeIntervalSince(cached.fetchedAt) < 30 * 86400 {
            return cached.cities
        }
        if let retry = state.searchRetry, retry.nextAttempt > now {
            throw ProviderError.http(429, retryAfter: retry.nextAttempt.timeIntervalSince(now))
        }
        guard let searchProvider else { return [] }
        do {
            let cities = try await searchProvider.search(trimmed)
            try Task.checkCancellation()
            state.searchRetry = nil
            state.searches = state.searches.filter { now.timeIntervalSince($0.value.fetchedAt) < 30 * 86400 }
            // Bound local disk use even with frequent searches.
            if state.searches.count >= 200, let oldest = state.searches.min(by: { $0.value.fetchedAt < $1.value.fetchedAt })?.key { state.searches[oldest] = nil }
            state.searches[key] = SearchCacheEntry(fetchedAt: now, cities: cities)
            persist()
            return cities
        } catch {
            if error is CancellationError || (error as? URLError)?.code == .cancelled { throw CancellationError() }
            state.searchRetry = retryState(error, previous: state.searchRetry)
            persist()
            throw error
        }
    }
    private func boundedJitter() -> TimeInterval { min(ForecastRefreshPolicy.maximumJitter, max(0, jitter())) }
    private func retryState(_ error: any Error, previous: RetryState?) -> RetryState {
        let failures = min((previous?.failures ?? 0) + 1, 100)
        let intervals: [TimeInterval] = [60, 300, 900, 3600]
        var delay = intervals[min(failures - 1, 3)] + boundedJitter() / 15
        if case ProviderError.http(let code, let retryAfter) = error {
            if let retryAfter { delay = max(delay, retryAfter) }
            else if (400..<500).contains(code), code != 429 { delay = 86400 }
        }
        return RetryState(failures: failures, nextAttempt: clock.now.addingTimeInterval(delay), message: error.localizedDescription)
    }
    private func persist() {
        do { try persistence.save(state); persistenceWarning = nil }
        catch { persistenceWarning = "Could not save the cache: \(error.localizedDescription)" }
    }
}
