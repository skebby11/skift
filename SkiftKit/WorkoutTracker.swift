import Foundation

/// Snapshot of where a workout's step sequence stands at a given ride-clock
/// elapsed time. Pure read model returned by `WorkoutTracker.state(atElapsed:)`.
public struct TrackerState: Equatable {
    public let currentStepIndex: Int
    public let currentStep: WorkoutStep
    public let secondsLeftInStep: TimeInterval
    public let nextStep: WorkoutStep?
    public let isFinished: Bool
}

/// Pure step-sequence lookup over a `Workout`, driven by the ride clock
/// (`RideEngine.elapsedSeconds`) rather than wall-clock time, so auto-pause
/// freezes the workout for free — the engine simply stops advancing elapsed
/// time while paused, and this type never notices.
///
/// `skipCurrentStep` and `adjustWatts` never mutate the underlying `Workout`:
/// they adjust an internal time offset / watts offset applied whenever
/// `state(atElapsed:)` is read.
public final class WorkoutTracker {

    private let workout: Workout
    /// Cumulative start time (seconds since workout start) of each step.
    private let stepStarts: [TimeInterval]
    private let totalDuration: TimeInterval

    /// Rebased on every `skipCurrentStep` so `elapsed - timeOffset` lands
    /// exactly where the tracker should report right now.
    private var timeOffset: TimeInterval = 0
    /// Global watts bump from `adjustWatts(by:)`, applied to every step's
    /// reported target — including the next step, not just the current one —
    /// and clamped so no step is ever reported below 0 W.
    private var wattsOffset: Int = 0

    public init(workout: Workout) {
        self.workout = workout
        var starts: [TimeInterval] = []
        var running: TimeInterval = 0
        for step in workout.steps {
            starts.append(running)
            running += step.durationSeconds
        }
        self.stepStarts = starts
        self.totalDuration = running
    }

    /// Current step, countdown and finish status at `elapsed` seconds into
    /// the ride clock.
    public func state(atElapsed elapsed: TimeInterval) -> TrackerState {
        state(atAdjustedElapsed: elapsed - timeOffset)
    }

    /// Ends the current step early: the next step (if any) starts exactly
    /// at `elapsed`. Skipping the final step finishes the workout outright.
    public func skipCurrentStep(atElapsed elapsed: TimeInterval) {
        let adjusted = elapsed - timeOffset
        let index = stepIndex(atAdjustedElapsed: adjusted)
        let nextStart = index + 1 < stepStarts.count ? stepStarts[index + 1] : totalDuration
        timeOffset += adjusted - nextStart
    }

    /// Bumps every step's reported target watts (current and upcoming) by
    /// `delta`, accumulating across calls — the classic head-unit ±5 W bump.
    public func adjustWatts(by delta: Int) {
        wattsOffset += delta
    }

    // MARK: - Private

    /// Index of the step containing `adjusted` (clamped to the last step
    /// once past the total duration). Boundaries are half-open: an elapsed
    /// time exactly at a step's end belongs to the NEXT step.
    private func stepIndex(atAdjustedElapsed adjusted: TimeInterval) -> Int {
        guard !workout.steps.isEmpty else { return 0 }
        for index in stride(from: workout.steps.count - 1, through: 0, by: -1) where adjusted >= stepStarts[index] {
            return index
        }
        return 0
    }

    private func state(atAdjustedElapsed adjusted: TimeInterval) -> TrackerState {
        guard !workout.steps.isEmpty else {
            let empty = WorkoutStep(label: "", targetWatts: 0, durationSeconds: 0)
            return TrackerState(currentStepIndex: 0, currentStep: empty, secondsLeftInStep: 0, nextStep: nil, isFinished: true)
        }

        guard adjusted < totalDuration else {
            let lastIndex = workout.steps.count - 1
            return TrackerState(
                currentStepIndex: lastIndex,
                currentStep: adjustedStep(workout.steps[lastIndex]),
                secondsLeftInStep: 0,
                nextStep: nil,
                isFinished: true
            )
        }

        let index = stepIndex(atAdjustedElapsed: adjusted)
        let step = workout.steps[index]
        let stepEnd = stepStarts[index] + step.durationSeconds
        let next = index + 1 < workout.steps.count ? adjustedStep(workout.steps[index + 1]) : nil

        return TrackerState(
            currentStepIndex: index,
            currentStep: adjustedStep(step),
            secondsLeftInStep: stepEnd - adjusted,
            nextStep: next,
            isFinished: false
        )
    }

    private func adjustedStep(_ step: WorkoutStep) -> WorkoutStep {
        WorkoutStep(
            label: step.label,
            targetWatts: max(0, step.targetWatts + wattsOffset),
            durationSeconds: step.durationSeconds
        )
    }
}
