import Foundation

/// One recorded instant of a ride, sampled once per simulated second.
/// Codable so `RideStore` can persist and reload it verbatim (see
/// docs/ride-history.md) — synthesized here, in the same file as the
/// declaration, rather than via an extension in RideStore.swift, since
/// cross-file extensions don't get automatic Codable synthesis.
public struct RideSample: Equatable, Codable {
    /// Seconds since the ride started.
    public let timeOffset: TimeInterval
    public let powerWatts: Int?
    public let cadenceRpm: Double?
    public let heartRateBpm: Int?
    public let speedKmh: Double
    /// Cumulative distance since the ride started (not wrapped per lap).
    public let distanceMeters: Double
    public let elevationMeters: Double

    public init(
        timeOffset: TimeInterval,
        powerWatts: Int?,
        cadenceRpm: Double?,
        heartRateBpm: Int?,
        speedKmh: Double,
        distanceMeters: Double,
        elevationMeters: Double
    ) {
        self.timeOffset = timeOffset
        self.powerWatts = powerWatts
        self.cadenceRpm = cadenceRpm
        self.heartRateBpm = heartRateBpm
        self.speedKmh = speedKmh
        self.distanceMeters = distanceMeters
        self.elevationMeters = elevationMeters
    }
}

/// Collects ride samples and turns them into a post-ride summary.
/// Pure accumulation — the ride engine decides when to append.
public final class RideRecorder {

    public private(set) var startDate: Date?
    public private(set) var samples: [RideSample] = []

    public init() {}

    /// Starts a fresh recording, discarding any previous samples.
    public func begin(at date: Date = Date()) {
        startDate = date
        samples = []
    }

    public func append(_ sample: RideSample) {
        samples.append(sample)
    }

    // MARK: - Summary

    public struct Summary: Equatable {
        public let durationSeconds: TimeInterval
        public let distanceMeters: Double
        public let averagePowerWatts: Double
        public let maxPowerWatts: Int
        public let averageCadenceRpm: Double?
        public let averageHeartRateBpm: Double?
        /// Sum of positive elevation deltas ("total ascent").
        public let elevationGainMeters: Double
        /// Mechanical work at the pedals, ∑ power·dt. Also the conventional
        /// calorie estimate: for cycling, kJ ≈ kcal (≈24% muscular efficiency).
        public let energyKilojoules: Double
    }

    /// nil until at least two samples exist (no meaningful stats before that).
    public var summary: Summary? {
        guard samples.count >= 2, let first = samples.first, let last = samples.last else { return nil }

        let powers = samples.compactMap(\.powerWatts)
        let cadences = samples.compactMap(\.cadenceRpm)
        let heartRates = samples.compactMap(\.heartRateBpm)

        var gain = 0.0
        var energyJoules = 0.0
        for index in 1..<samples.count {
            let delta = samples[index].elevationMeters - samples[index - 1].elevationMeters
            if delta > 0 { gain += delta }
            let dt = samples[index].timeOffset - samples[index - 1].timeOffset
            energyJoules += Double(samples[index].powerWatts ?? 0) * dt
        }

        return Summary(
            durationSeconds: last.timeOffset - first.timeOffset,
            distanceMeters: last.distanceMeters - first.distanceMeters,
            averagePowerWatts: powers.isEmpty ? 0 : Double(powers.reduce(0, +)) / Double(powers.count),
            maxPowerWatts: powers.max() ?? 0,
            averageCadenceRpm: cadences.isEmpty ? nil : cadences.reduce(0, +) / Double(cadences.count),
            averageHeartRateBpm: heartRates.isEmpty ? nil : Double(heartRates.reduce(0, +)) / Double(heartRates.count),
            elevationGainMeters: gain,
            energyKilojoules: energyJoules / 1000
        )
    }
}
