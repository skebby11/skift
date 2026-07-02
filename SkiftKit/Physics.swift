import Foundation

/// Rider + bike parameters that feed the physics model.
public struct RiderProfile: Equatable {
    public var riderKg: Double
    public var bikeKg: Double
    /// Rolling resistance coefficient (road tires on asphalt ≈ 0.004).
    public var crr: Double
    /// Effective frontal area × drag coefficient, m² (road hoods ≈ 0.32).
    public var cda: Double

    public var totalKg: Double { riderKg + bikeKg }

    public init(riderKg: Double = 75, bikeKg: Double = 8, crr: Double = 0.004, cda: Double = 0.32) {
        self.riderKg = riderKg
        self.bikeKg = bikeKg
        self.crr = crr
        self.cda = cda
    }
}

/// Converts pedaling power into speed by integrating the road-cycling force
/// balance (drive vs. gravity, rolling resistance and aero drag). Integration
/// instead of steady-state solving makes starts, coasting and descents behave
/// naturally: at 0 W on a descent gravity still accelerates the rider.
public struct PhysicsEngine {

    public static let airDensityKgM3 = 1.226
    public static let gravityMS2 = 9.81

    public var profile: RiderProfile
    public private(set) var speedMS: Double = 0

    public init(profile: RiderProfile = RiderProfile()) {
        self.profile = profile
    }

    /// Advances the simulation by `dt` seconds and returns the new speed (m/s).
    @discardableResult
    public mutating func step(powerWatts: Double, gradePercent: Double, dt: Double) -> Double {
        let mass = profile.totalKg
        let theta = atan(gradePercent / 100)

        // Drive force is P/v; floor the divisor to avoid the standing-start
        // singularity (equivalent to capping force at P watts per 1 m/s).
        let driveForce = max(powerWatts, 0) / max(speedMS, 1.0)
        let gravityForce = -mass * Self.gravityMS2 * sin(theta)
        let rollingForce = speedMS > 0 ? -mass * Self.gravityMS2 * profile.crr * cos(theta) : 0
        let dragForce = -0.5 * Self.airDensityKgM3 * profile.cda * speedMS * speedMS

        let acceleration = (driveForce + gravityForce + rollingForce + dragForce) / mass
        speedMS = max(0, speedMS + acceleration * dt)
        return speedMS
    }

    /// Resistive power required to hold `speedMS` on the given grade — the
    /// steady-state counterpart of `step`, useful for tests and pacing HUDs.
    public func requiredPower(atSpeedMS v: Double, gradePercent: Double) -> Double {
        let mass = profile.totalKg
        let theta = atan(gradePercent / 100)
        let rollingAndGravity = mass * Self.gravityMS2 * (sin(theta) + profile.crr * cos(theta))
        let drag = 0.5 * Self.airDensityKgM3 * profile.cda * v * v
        return (rollingAndGravity + drag) * v
    }
}
