import Foundation

/// Anything that can receive a grade command — `TrainerManager` in the app,
/// a fake in tests.
public protocol TrainerControlling: AnyObject {
    func setGrade(percent: Double)
}

extension TrainerManager: TrainerControlling {}

/// The game loop: reads power from an injected source, steps the physics,
/// advances the rider along the route, and keeps the trainer's resistance in
/// sync with the terrain.
public final class RideEngine: ObservableObject {

    @Published public private(set) var isRiding = false
    @Published public private(set) var speedKmh: Double = 0
    @Published public private(set) var distanceMeters: Double = 0
    @Published public private(set) var totalDistanceMeters: Double = 0
    @Published public private(set) var gradientPercent: Double
    @Published public private(set) var elevationMeters: Double

    /// Fraction of the real gradient sent to the trainer (Zwift's "trainer
    /// difficulty"); physics always uses the full gradient, so this changes
    /// how climbs FEEL, not how fast the avatar goes.
    /// REVIEW: 0.5 matches Zwift's default; exposed in Settings (M4).
    public var trainerDifficulty: Double = 0.5

    public let route: Route

    /// Recording of the current (or last) ride; fed one sample per simulated
    /// second while riding. Read it after `stop()` for the summary/export.
    public private(set) var recorder = RideRecorder()

    private var physics: PhysicsEngine
    /// Polled every tick for the trainer's latest data (power drives the
    /// physics; cadence and heart rate flow into the recorder).
    private var dataSource: () -> FTMS.IndoorBikeData = { FTMS.IndoorBikeData() }
    private weak var control: TrainerControlling?
    private var timer: Timer?
    private var lastSentGrade: Double?
    private var timeSinceGradeSent: Double = .infinity
    private var timeSinceSample: Double = 0
    private var rideClock: Double = 0

    private static let tickSeconds = 0.1
    private static let gradeSendThresholdPercent = 0.1
    private static let gradeSendMinIntervalSeconds = 1.0
    private static let sampleIntervalSeconds = 1.0

    public init(route: Route, profile: RiderProfile = RiderProfile()) {
        self.route = route
        self.physics = PhysicsEngine(profile: profile)
        self.gradientPercent = route.gradient(atMeters: 0)
        self.elevationMeters = route.elevation(atMeters: 0)
    }

    /// Starts the 10 Hz loop. `dataSource` is polled every tick for the
    /// trainer's latest data; `control` receives the scaled gradient;
    /// `profile` (when given) applies the rider's settings to the physics.
    public func start(
        dataSource: @escaping () -> FTMS.IndoorBikeData,
        control: TrainerControlling?,
        profile: RiderProfile? = nil
    ) {
        self.dataSource = dataSource
        self.control = control
        if let profile {
            physics = PhysicsEngine(profile: profile)
        }
        lastSentGrade = nil
        timeSinceGradeSent = .infinity
        timeSinceSample = 0
        rideClock = 0
        totalDistanceMeters = 0
        distanceMeters = 0
        recorder = RideRecorder()
        recorder.begin()
        isRiding = true
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: Self.tickSeconds, repeats: true) { [weak self] _ in
            self?.step(dt: Self.tickSeconds)
        }
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
        isRiding = false
    }

    /// One simulation tick. Public so tests can drive the engine without the timer.
    public func step(dt: Double) {
        let data = dataSource()
        let speedMS = physics.step(
            powerWatts: Double(data.powerWatts ?? 0),
            gradePercent: gradientPercent,
            dt: dt
        )
        speedKmh = speedMS * 3.6
        totalDistanceMeters += speedMS * dt
        distanceMeters = totalDistanceMeters.truncatingRemainder(dividingBy: route.lengthMeters)
        gradientPercent = route.gradient(atMeters: distanceMeters)
        elevationMeters = route.elevation(atMeters: distanceMeters)
        rideClock += dt
        syncGradeToTrainer(dt: dt)
        recordSampleIfDue(dt: dt, data: data)
    }

    /// Appends one sample per simulated second to the recorder.
    private func recordSampleIfDue(dt: Double, data: FTMS.IndoorBikeData) {
        timeSinceSample += dt
        guard timeSinceSample >= Self.sampleIntervalSeconds else { return }
        timeSinceSample = 0
        recorder.append(RideSample(
            timeOffset: rideClock,
            powerWatts: data.powerWatts,
            cadenceRpm: data.cadenceRpm,
            heartRateBpm: data.heartRateBpm,
            speedKmh: speedKmh,
            distanceMeters: totalDistanceMeters,
            elevationMeters: elevationMeters
        ))
    }

    private func syncGradeToTrainer(dt: Double) {
        timeSinceGradeSent += dt
        guard timeSinceGradeSent >= Self.gradeSendMinIntervalSeconds else { return }

        let target = gradientPercent * trainerDifficulty
        let changedEnough = lastSentGrade.map {
            abs($0 - target) >= Self.gradeSendThresholdPercent
        } ?? true
        guard changedEnough else { return }

        control?.setGrade(percent: target)
        lastSentGrade = target
        timeSinceGradeSent = 0
    }
}
