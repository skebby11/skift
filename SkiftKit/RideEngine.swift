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

    // Live trainer data, republished per tick so the ride HUD binds to the
    // engine alone. Watts is the headline number of the whole app: training
    // is power-based and the D500 measures it directly.
    @Published public private(set) var powerWatts: Int = 0
    @Published public private(set) var cadenceRpm: Double?
    @Published public private(set) var heartRateBpm: Int?

    /// Simulated ride clock for the HUD (seconds since "Start ride").
    @Published public private(set) var elapsedSeconds: Double = 0
    /// Optional finish line, in cumulative meters. When crossed the engine
    /// completes the ride on its own (stops the loop, flips `isCompleted`).
    @Published public private(set) var targetDistanceMeters: Double?
    /// True once the target distance has been reached (never set on free rides).
    @Published public private(set) var isCompleted = false
    /// Zwift-style auto-pause: no power AND (nearly) no speed. The ride clock
    /// and the recorder stop so dead time doesn't pollute averages; coasting
    /// downhill at 0 W keeps the clock running (speed condition).
    @Published public private(set) var isAutoPaused = false

    /// The rider profile currently driving the physics (exposed for W/kg).
    public var riderProfile: RiderProfile { physics.profile }

    /// Fraction of the real gradient sent to the trainer (Zwift's "trainer
    /// difficulty"); physics always uses the full gradient, so this changes
    /// how climbs FEEL, not how fast the avatar goes.
    /// REVIEW: 0.5 matches Zwift's default; exposed in Settings (M4).
    public var trainerDifficulty: Double = 0.5

    public let route: Route

    /// 3D placement of the route, built once (the spline sampling isn't free,
    /// so views must not rebuild it per frame).
    public let layout: TrackLayout

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
        self.layout = TrackLayout(route: route)
        self.physics = PhysicsEngine(profile: profile)
        // Smoothed gradient everywhere the rider can feel it (see Route).
        self.gradientPercent = route.smoothedGradient(atMeters: 0)
        self.elevationMeters = route.elevation(atMeters: 0)
    }

    /// Starts the 10 Hz loop. `dataSource` is polled every tick for the
    /// trainer's latest data; `control` receives the scaled gradient;
    /// `profile` (when given) applies the rider's settings to the physics.
    public func start(
        dataSource: @escaping () -> FTMS.IndoorBikeData,
        control: TrainerControlling?,
        profile: RiderProfile? = nil,
        targetDistanceMeters: Double? = nil
    ) {
        self.dataSource = dataSource
        self.control = control
        self.targetDistanceMeters = targetDistanceMeters
        isCompleted = false
        elapsedSeconds = 0
        // Always rebuild the physics: a fresh ride starts from a standstill,
        // not at whatever speed the previous ride ended with.
        physics = PhysicsEngine(profile: profile ?? physics.profile)
        lastSentGrade = nil
        timeSinceGradeSent = .infinity
        timeSinceSample = 0
        rideClock = 0
        totalDistanceMeters = 0
        distanceMeters = 0
        speedKmh = 0
        gradientPercent = route.smoothedGradient(atMeters: 0)
        elevationMeters = route.elevation(atMeters: 0)
        recorder = RideRecorder()
        recorder.begin()
        isAutoPaused = false
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
        gradientPercent = route.smoothedGradient(atMeters: distanceMeters)
        elevationMeters = route.elevation(atMeters: distanceMeters)
        powerWatts = data.powerWatts ?? 0
        cadenceRpm = data.cadenceRpm
        heartRateBpm = data.heartRateBpm

        isAutoPaused = powerWatts == 0 && speedMS < 0.1
        if !isAutoPaused {
            rideClock += dt
            elapsedSeconds = rideClock
            recordSampleIfDue(dt: dt, data: data)
        }
        syncGradeToTrainer(dt: dt) // resistance stays correct even while paused

        // Auto-complete when the chosen target distance is reached: stop the
        // loop (no further grade commands) and let the UI move to the summary.
        // Guarded on isCompleted (not isRiding) so it fires exactly once even
        // if steps are driven externally (tests) after the timer stopped.
        if let target = targetDistanceMeters, totalDistanceMeters >= target, !isCompleted {
            isCompleted = true
            stop()
        }
    }

    /// Appends one sample per simulated second to the recorder.
    /// The epsilon absorbs float accumulation (ten 0.1 ticks sum to
    /// 0.9999999…); carrying the remainder keeps the cadence drift-free.
    private func recordSampleIfDue(dt: Double, data: FTMS.IndoorBikeData) {
        timeSinceSample += dt
        guard timeSinceSample >= Self.sampleIntervalSeconds - 1e-9 else { return }
        timeSinceSample -= Self.sampleIntervalSeconds
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
        // Same float-accumulation epsilon as the sampler.
        guard timeSinceGradeSent >= Self.gradeSendMinIntervalSeconds - 1e-9 else { return }

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
