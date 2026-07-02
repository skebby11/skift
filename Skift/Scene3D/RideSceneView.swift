import RealityKit
import SkiftKit
import SwiftUI

/// Hosts the 3D world in SwiftUI. `ARView` is used as a plain (non-AR) 3D
/// view — unlike SwiftUI's `RealityView` it is available on macOS 14.
/// The parent view re-renders at the ride engine's tick rate (10 Hz), so
/// `updateNSView` doubles as the per-tick avatar/camera update.
///
/// REVIEW: 10 Hz updates may look steppy at speed; if so, move the camera
/// update into an `arView.scene.subscribe(to: SceneEvents.Update.self)`
/// callback (per-frame, 60+ Hz) and interpolate the engine's distance.
struct RideSceneView: NSViewRepresentable {

    let layout: TrackLayout
    let distanceMeters: Double

    /// Keeps references to the entities that move every tick, plus the
    /// smoothed camera position carried across updates.
    final class Coordinator {
        var avatar: Entity?
        var camera: PerspectiveCamera?
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

        let avatar = WorldBuilder.makeAvatar()
        anchor.addChild(avatar)
        context.coordinator.avatar = avatar

        let camera = PerspectiveCamera()
        anchor.addChild(camera)
        context.coordinator.camera = camera

        arView.scene.addAnchor(anchor)
        moveAvatarAndCamera(context.coordinator)
        return arView
    }

    func updateNSView(_ nsView: ARView, context: Context) {
        moveAvatarAndCamera(context.coordinator)
    }

    /// Places the avatar on the road at the current distance and eases the
    /// chase camera toward its target pose.
    private func moveAvatarAndCamera(_ coordinator: Coordinator) {
        guard let avatar = coordinator.avatar, let camera = coordinator.camera else { return }
        let position = layout.position(atMeters: distanceMeters)
        let tangent = layout.tangent(atMeters: distanceMeters)

        // The tangent includes the slope's vertical component, so looking
        // along it pitches the avatar up/down hills automatically.
        avatar.look(at: position + tangent, from: position, relativeTo: nil)

        // Chase camera: 10 m behind, 4 m up, looking slightly above the
        // rider. Exponential smoothing hides the 10 Hz steps and the spline's
        // segment corners. REVIEW: camera distance/height and smoothing
        // factor are feel parameters — tune on screen.
        let targetCameraPosition = position - tangent * 10 + SIMD3<Float>(0, 4, 0)
        let smoothed: SIMD3<Float>
        if let previous = coordinator.smoothedCameraPosition {
            smoothed = simd_mix(previous, targetCameraPosition, SIMD3(repeating: 0.25))
        } else {
            smoothed = targetCameraPosition
        }
        coordinator.smoothedCameraPosition = smoothed
        camera.look(at: position + SIMD3<Float>(0, 1.2, 0), from: smoothed, relativeTo: nil)
    }
}
