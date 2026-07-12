import Foundation

/// One flat step of a structured workout: hold `targetWatts` for
/// `durationSeconds`, then move on. `label` is what the ERG HUD shows
/// ("Warmup", "Work 2/6", ...).
public struct WorkoutStep: Codable, Equatable {
    public let label: String
    public let targetWatts: Int
    public let durationSeconds: TimeInterval

    public init(label: String, targetWatts: Int, durationSeconds: TimeInterval) {
        self.label = label
        self.targetWatts = targetWatts
        self.durationSeconds = durationSeconds
    }
}

/// A structured, ERG-mode workout: a name and a flat list of steps. Built
/// either directly or via the `intervals` factory (warmup → N×(work +
/// recovery) → cooldown), which is all the v1 builder UI needs
/// (docs/erg-mode.md).
public struct Workout: Codable, Identifiable, Equatable {
    public let id: UUID
    public var name: String
    public var steps: [WorkoutStep]

    public init(id: UUID = UUID(), name: String, steps: [WorkoutStep]) {
        self.id = id
        self.name = name
        self.steps = steps
    }

    /// Sum of every step's duration — the workout's total ride time.
    public var totalDurationSeconds: TimeInterval {
        steps.reduce(0) { $0 + $1.durationSeconds }
    }

    /// Flattens a warmup / N×(work + recovery) / cooldown structure into a
    /// flat step list. Each part is `(watts, seconds)`; parts with zero
    /// duration are skipped entirely (no empty steps), but repeat labels
    /// ("Work i/N", "Recovery i/N") always report the full repeat count,
    /// not a renumbered sequence over the parts that survived.
    public static func intervals(
        name: String,
        warmup: (watts: Int, seconds: TimeInterval),
        repeats: Int,
        work: (watts: Int, seconds: TimeInterval),
        recovery: (watts: Int, seconds: TimeInterval),
        cooldown: (watts: Int, seconds: TimeInterval)
    ) -> Workout {
        var steps: [WorkoutStep] = []

        if warmup.seconds > 0 {
            steps.append(WorkoutStep(label: "Warmup", targetWatts: warmup.watts, durationSeconds: warmup.seconds))
        }

        if repeats > 0 {
            for i in 1...repeats {
                if work.seconds > 0 {
                    steps.append(WorkoutStep(
                        label: "Work \(i)/\(repeats)",
                        targetWatts: work.watts,
                        durationSeconds: work.seconds
                    ))
                }
                if recovery.seconds > 0 {
                    steps.append(WorkoutStep(
                        label: "Recovery \(i)/\(repeats)",
                        targetWatts: recovery.watts,
                        durationSeconds: recovery.seconds
                    ))
                }
            }
        }

        if cooldown.seconds > 0 {
            steps.append(WorkoutStep(label: "Cooldown", targetWatts: cooldown.watts, durationSeconds: cooldown.seconds))
        }

        return Workout(name: name, steps: steps)
    }
}
