import RealityKit
import SkiftKit
import SwiftUI

/// Hosts the 3D world in SwiftUI. `ARView` is used as a plain (non-AR) 3D
/// view — unlike SwiftUI's `RealityView` it is available on macOS 14.
/// The parent view re-renders at the ride engine's tick rate, so
/// `updateNSView` doubles as the per-tick avatar/camera update.
struct RideSceneView: NSViewRepresentable {

    let layout: TrackLayout
    let distanceMeters: Double

    final class Coordinator {
        var avatar: Entity?
        var camera: PerspectiveCamera?
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        arView.environment.background = .color(
            NSColor(red: 0.55, green: 0.75, blue: 0.95, alpha: 1)
        )

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

    private func moveAvatarAndCamera(_ coordinator: Coordinator) {
        guard let avatar = coordinator.avatar, let camera = coordinator.camera else { return }
        let position = layout.position(atMeters: distanceMeters)
        let tangent = layout.tangent(atMeters: distanceMeters)

        avatar.look(at: position + tangent, from: position, relativeTo: nil)

        let cameraPosition = position - tangent * 10 + SIMD3<Float>(0, 4, 0)
        camera.look(at: position + SIMD3<Float>(0, 1.2, 0), from: cameraPosition, relativeTo: nil)
    }
}
