import Combine
import RealityKit
import SkiftKit
import SwiftUI

/// Hosts the 3D world in SwiftUI. `ARView` is used as a plain (non-AR) 3D
/// view — unlike SwiftUI's `RealityView` it is available on macOS 14.
///
/// Animation architecture (docs/avatar-gamefeel.md): SwiftUI updates arrive
/// at the engine's 10 Hz tick and only refresh the coordinator's *targets*
/// (distance, speed, cadence). The actual motion — avatar, camera, wheels,
/// pedals — runs in a `SceneEvents.Update` subscription at render rate
/// (60+ Hz), interpolating a display distance toward the engine's
/// authoritative one. The engine stays the single source of truth; the
/// renderer just smooths it.
struct RideSceneView: NSViewRepresentable {

    let layout: TrackLayout
    let distanceMeters: Double
    let speedKmh: Double
    let cadenceRpm: Double

    /// Mutable render state shared between SwiftUI updates (writes targets)
    /// and the per-frame handler (reads targets, owns display state).
    final class Coordinator {
        var layout: TrackLayout?
        var rig: WorldBuilder.AvatarRig?
        var camera: PerspectiveCamera?
        var updateSubscription: Cancellable?

        // Targets, refreshed by updateNSView at the engine tick.
        var targetDistance: Double = 0
        var speedMS: Double = 0
        var cadenceRpm: Double = 0

        // Display state, owned by the per-frame handler.
        var displayDistance: Double = 0
        var wheelAngle: Float = 0
        var pedalAngle: Float = 0
        var smoothedCameraPosition: SIMD3<Float>?
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        // Flat sky color for now. REVIEW: replace with a gradient/skybox
        // (environment.background supports a skybox texture) in the art pass.
        arView.environment.background = .color(
            NSColor(red: 0.55, green: 0.75, blue: 0.95, alpha: 1)
        )

        // One static world anchor at the origin holds everything.
        let anchor = AnchorEntity(world: SIMD3<Float>(0, 0, 0))
        if let world = try? WorldBuilder.makeWorld(layout: layout) {
            anchor.addChild(world)
        }

        let rig = WorldBuilder.makeAvatar()
        anchor.addChild(rig.root)

        let camera = PerspectiveCamera()
        anchor.addChild(camera)
        arView.scene.addAnchor(anchor)

        let coordinator = context.coordinator
        coordinator.layout = layout
        coordinator.rig = rig
        coordinator.camera = camera
        coordinator.displayDistance = distanceMeters
        pushTargets(into: coordinator)

        // Per-frame animation. Weak coordinator breaks the retain cycle
        // (coordinator → subscription → closure → coordinator).
        coordinator.updateSubscription = arView.scene.subscribe(to: SceneEvents.Update.self) { [weak coordinator] event in
            coordinator?.stepFrame(dt: event.deltaTime)
        }
        return arView
    }

    func updateNSView(_ nsView: ARView, context: Context) {
        pushTargets(into: context.coordinator)
    }

    private func pushTargets(into coordinator: Coordinator) {
        coordinator.targetDistance = distanceMeters
        coordinator.speedMS = speedKmh / 3.6
        coordinator.cadenceRpm = cadenceRpm
    }
}

extension RideSceneView.Coordinator {

    /// One rendered frame: advance the display distance by current speed,
    /// correct it toward the engine's value, then pose everything.
    func stepFrame(dt: TimeInterval) {
        guard let layout, let rig, let camera else { return }
        let length = layout.route.lengthMeters

        // Dead-reckon with the current speed, then pull toward the engine's
        // distance along the shortest wrap-aware difference (~1/3 s time
        // constant): imperceptible corrections, no rubber-banding.
        displayDistance += speedMS * dt
        var correction = targetDistance - displayDistance.truncatingRemainder(dividingBy: length)
        correction -= (correction / length).rounded() * length
        displayDistance += correction * min(1, dt * 3)

        let position = layout.position(atMeters: displayDistance)
        let tangent = layout.tangent(atMeters: displayDistance)

        // The tangent includes the slope's vertical component, so looking
        // along it pitches the avatar up/down hills automatically.
        rig.root.look(at: position + tangent, from: position, relativeTo: nil)

        spinParts(dt: dt, rig: rig)

        // Chase camera: 10 m behind, 4 m up, exponential ease per frame.
        // REVIEW: distance/height/easing are feel parameters — tune on screen.
        let cameraTarget = position - tangent * 10 + SIMD3<Float>(0, 4, 0)
        let blend = Float(1 - exp(-4 * dt))
        let smoothed = smoothedCameraPosition.map { simd_mix($0, cameraTarget, SIMD3(repeating: blend)) } ?? cameraTarget
        smoothedCameraPosition = smoothed
        camera.look(at: position + SIMD3<Float>(0, 1.2, 0), from: smoothed, relativeTo: nil)
    }

    /// Wheels spin with road speed (ω = v/r); pedals orbit the crank with
    /// real cadence, in opposite phase.
    private func spinParts(dt: TimeInterval, rig: WorldBuilder.AvatarRig) {
        wheelAngle -= Float(speedMS / Double(WorldBuilder.AvatarRig.wheelRadius) * dt)
        for wheel in rig.wheels {
            wheel.orientation = simd_quatf(angle: wheelAngle, axis: SIMD3(1, 0, 0))
        }

        pedalAngle += Float(cadenceRpm / 60 * 2 * .pi * dt)
        for (index, pedal) in rig.pedals.enumerated() {
            let phase = pedalAngle + (index == 0 ? 0 : .pi)
            let center = WorldBuilder.AvatarRig.crankCenter
            pedal.position = SIMD3(
                pedal.position.x, // keep the lateral offset set at build time
                center.y - WorldBuilder.AvatarRig.crankRadius * cos(phase),
                center.z + WorldBuilder.AvatarRig.crankRadius * sin(phase)
            )
        }
    }
}
