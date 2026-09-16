import Foundation

struct RetryState: Codable, Sendable {
    var failures: Int
    var nextAttempt: Date
    var message: String
}
struct SearchCacheEntry: Codable, Sendable {
    let fetchedAt: Date
    let cities: [SavedCity]
}
struct RepositorySnapshot: Codable, Sendable {
    var version = 1
    var cities: [SavedCity] = []
    var forecasts: [Int: CityForecast] = [:]
    var scheduled: [Int: Date] = [:]
    var retries: [Int: RetryState] = [:]
    var searches: [String: SearchCacheEntry] = [:]
    var searchRetry: RetryState?
}
protocol SnapshotPersistence: Sendable {
    func load() throws -> RepositorySnapshot?
    func save(_ snapshot: RepositorySnapshot) throws
}
struct DiskPersistence: SnapshotPersistence {
    let file: URL
    init(directory: URL) { file = directory.appendingPathComponent("state-v1.json") }
    static func applicationSupport() throws -> Self {
        let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return Self(directory: support.appendingPathComponent("Udara", isDirectory: true))
    }
    func load() throws -> RepositorySnapshot? {
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        let result = try JSONDecoder().decode(RepositorySnapshot.self, from: Data(contentsOf: file))
        guard result.version == 1 else { throw PersistenceError.unsupportedVersion }
        return result
    }
    func save(_ snapshot: RepositorySnapshot) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(snapshot).write(to: file, options: [.atomic, .completeFileProtectionUnlessOpen])
    }
}
enum PersistenceError: Error, LocalizedError {
    case unsupportedVersion
    var errorDescription: String? { "This saved data uses an unsupported version. Its file has been preserved." }
}
/// Used only by previews and tests; never points to the production container.
final class MemoryPersistence: SnapshotPersistence, @unchecked Sendable {
    private let lock = NSLock()
    private var value: RepositorySnapshot?
    func load() throws -> RepositorySnapshot? { lock.withLock { value } }
    func save(_ snapshot: RepositorySnapshot) throws { lock.withLock { value = snapshot } }
}
