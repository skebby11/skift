import Foundation

public enum WorkoutStoreError: Error, Equatable {
    /// `delete(id:)` found no file for that id.
    case workoutNotFound
}

/// Filesystem-backed local workout library: one JSON file per workout, named
/// by id so re-saving the same workout overwrites rather than duplicates.
/// Same pattern as `RideStore` — directory injected at init so tests use a
/// throwaway temp directory; the app uses `defaultDirectory` (inside the
/// sandboxed container's Application Support folder).
public final class WorkoutStore {

    public static var defaultDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Skift/workouts", isDirectory: true)
    }

    private let directory: URL
    private let fileManager: FileManager

    public init(directory: URL = WorkoutStore.defaultDirectory, fileManager: FileManager = .default) {
        self.directory = directory
        self.fileManager = fileManager
    }

    /// Persists a workout as one JSON file, creating the storage directory
    /// on demand. Saving a workout with an id already on disk overwrites it.
    @discardableResult
    public func save(_ workout: Workout) throws -> Workout {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(workout)
        try data.write(to: fileURL(for: workout), options: .atomic)
        return workout
    }

    /// All stored workouts, sorted by name.
    ///
    /// DECISION: a corrupt or unreadable file is skipped rather than thrown —
    /// mirrors `RideStore.list()` (docs/ride-history.md); a single bad file
    /// must never brick the workout picker.
    public func list() throws -> [Workout] {
        guard fileManager.fileExists(atPath: directory.path) else { return [] }

        let urls = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        let decoder = JSONDecoder()

        let workouts: [Workout] = urls.compactMap { url in
            guard url.pathExtension == "json", let data = try? Data(contentsOf: url) else { return nil }
            return try? decoder.decode(Workout.self, from: data)
        }
        return workouts.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Deletes the workout with the given id.
    public func delete(id: UUID) throws {
        let urls = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        guard let match = urls.first(where: { $0.lastPathComponent.contains(id.uuidString) }) else {
            throw WorkoutStoreError.workoutNotFound
        }
        try fileManager.removeItem(at: match)
    }

    private func fileURL(for workout: Workout) -> URL {
        directory.appendingPathComponent("\(workout.id.uuidString).json")
    }
}
