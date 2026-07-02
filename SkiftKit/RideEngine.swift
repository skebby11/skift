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

    private var physics: PhysicsEngine
    private var powerSource: () -> Double = { 0 }
    private weak var control: TrainerControlling?
    private var timer: Timer?
    private var lastSentGrade: Double?
    private var timeSinceGradeSent: Double = .infinity

    private static let tickSeconds = 0.1
    private static let gradeSendThresholdPercent = 0.1
    private static let gradeSendMinIntervalSeconds = 1.0

    public init(route: Route, profile: RiderProfile = RiderProfile()) {
        self.route = route
        self.physics = PhysicsEngine(profile: profile)
        self.gradientPercent = route.gradient(atMeters: 0)
        self.elevationMeters = route.elevation(atMeters: 0)
    }

    /// Starts the 10 Hz loop. `powerSource` is polled every tick (return the
    /// latest trainer power); `control` receives the scaled gradient.
    public func start(powerSource: @escaping () -> Double, control: TrainerControlling?) {
        self.powerSource = powerSource
        self.control = control
        lastSentGrade = nil
        timeSinceGradeSent = .infinity
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
        let speedMS = physics.step(powerWatts: powerSource(), gradePercent: gradientPercent, dt: dt)
        speedKmh = speedMS * 3.6
        totalDistanceMeters += speedMS * dt
        distanceMeters = totalDistanceMeters.truncatingRemainder(dividingBy: route.lengthMeters)
        gradientPercent = route.gradient(atMeters: distanceMeters)
        elevationMeters = route.elevation(atMeters: distanceMeters)
        syncGradeToTrainer(dt: dt)
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
