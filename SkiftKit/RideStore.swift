import Foundation

/// A ride persisted to disk: the summary numbers `HistoryView`'s list needs
/// plus the full sample stream, so re-exporting to TCX later produces
/// exactly what the post-ride export would have (see docs/ride-history.md).
public struct StoredRide: Codable, Identifiable, Equatable {
    public let id: UUID
    public let startDate: Date
    public let durationSeconds: TimeInterval
    public let distanceMeters: Double
    public let averagePowerWatts: Double
    public let samples: [RideSample]

    public init(
        id: UUID,
        startDate: Date,
        durationSeconds: TimeInterval,
        distanceMeters: Double,
        averagePowerWatts: Double,
        samples: [RideSample]
    ) {
        self.id = id
        self.startDate = startDate
        self.durationSeconds = durationSeconds
        self.distanceMeters = distanceMeters
        self.averagePowerWatts = averagePowerWatts
        self.samples = samples
    }
}

public enum RideStoreError: Error {
    /// `save(recorder:)` was called on a recorder with no meaningful summary
    /// (fewer than two samples) — nothing to persist.
    case nothingToSave
    /// `delete(id:)` found no file for that id.
    case rideNotFound
}

/// Filesystem-backed local ride history: one JSON file per ride. Directory
/// is injected at init so tests use a throwaway temp directory; the app
/// uses `defaultDirectory` (inside the sandboxed container's Application
/// Support folder).
public final class RideStore {

    public static var defaultDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Skift/rides", isDirectory: true)
    }

    private let directory: URL
    private let fileManager: FileManager

    public init(directory: URL = RideStore.defaultDirectory, fileManager: FileManager = .default) {
        self.directory = directory
        self.fileManager = fileManager
    }

    /// Persists the recorder's ride as one JSON file, creating the storage
    /// directory on demand.
    @discardableResult
    public func save(recorder: RideRecorder, date: Date = Date()) throws -> StoredRide {
        guard let startDate = recorder.startDate, let summary = recorder.summary else {
            throw RideStoreError.nothingToSave
        }

        let ride = StoredRide(
            id: UUID(),
            startDate: startDate,
            durationSeconds: summary.durationSeconds,
            distanceMeters: summary.distanceMeters,
            averagePowerWatts: summary.averagePowerWatts,
            samples: recorder.samples
        )

        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(ride)
        try data.write(to: fileURL(for: ride), options: .atomic)
        return ride
    }

    /// All stored rides, newest first.
    ///
    /// DECISION: a corrupt or unreadable file is skipped rather than
    /// thrown — a single bad file must never brick the History screen
    /// (docs/ride-history.md).
    public func list() throws -> [StoredRide] {
        guard fileManager.fileExists(atPath: directory.path) else { return [] }

        let urls = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let rides: [StoredRide] = urls.compactMap { url in
            guard url.pathExtension == "json", let data = try? Data(contentsOf: url) else { return nil }
            return try? decoder.decode(StoredRide.self, from: data)
        }
        return rides.sorted { $0.startDate > $1.startDate }
    }

    /// Deletes the ride with the given id.
    public func delete(id: UUID) throws {
        let urls = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        guard let match = urls.first(where: { $0.lastPathComponent.contains(id.uuidString) }) else {
            throw RideStoreError.rideNotFound
        }
        try fileManager.removeItem(at: match)
    }

    private func fileURL(for ride: StoredRide) -> URL {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        return directory.appendingPathComponent("\(iso.string(from: ride.startDate))-\(ride.id.uuidString).json")
    }
}
