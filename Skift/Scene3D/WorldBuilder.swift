import AppKit
import RealityKit
import SkiftKit

/// Builds the placeholder 3D world from a track layout: water, a green
/// island ribbon, the road, trees and a sun. Everything is generated from
/// primitives and `MeshDescriptor` — no art assets yet.
///
/// REVIEW: all colors, sizes and light intensity below are first-draft values
/// chosen blind; tune them on a real screen during the M3 art pass.
enum WorldBuilder {

    // MARK: - Palette (low-poly, slightly desaturated)

    private static let waterColor = NSColor(red: 0.15, green: 0.4, blue: 0.65, alpha: 1)
    private static let grassColor = NSColor(red: 0.35, green: 0.6, blue: 0.3, alpha: 1)
    private static let sandColor = NSColor(red: 0.86, green: 0.79, blue: 0.55, alpha: 1)
    private static let roadColor = NSColor(white: 0.35, alpha: 1)
    private static let trunkColor = NSColor(red: 0.45, green: 0.32, blue: 0.2, alpha: 1)
    private static let crownColor = NSColor(red: 0.22, green: 0.45, blue: 0.25, alpha: 1)

    // MARK: - World

    static func makeWorld(layout: TrackLayout) throws -> Entity {
        let root = Entity()

        // Sea level is y = 0; the route's lowest elevation is ~10 m, so the
        // island always sits above the water.
        let water = ModelEntity(
            mesh: .generatePlane(width: 8000, depth: 8000),
            materials: [SimpleMaterial(color: waterColor, isMetallic: false)]
        )
        root.addChild(water)

        // The "island" is three concentric ribbons that follow the road:
        // sand (widest, lowest), grass, then the road itself on top.
        // REVIEW: replace with a real heightmap coastline in the art pass —
        // ribbons leave visible gaps on the inside of tight corners.
        root.addChild(try ribbon(layout: layout, halfWidth: 70, yOffset: -6, color: sandColor))
        root.addChild(try ribbon(layout: layout, halfWidth: 45, yOffset: -0.5, color: grassColor))
        root.addChild(try ribbon(layout: layout, halfWidth: 4, yOffset: 0, color: roadColor))

        root.addChild(makeTrees(layout: layout))

        let sun = DirectionalLight()
        sun.light.intensity = 6000
        sun.look(at: SIMD3(0, 0, 0), from: SIMD3(1500, 2500, 1000), relativeTo: nil)
        root.addChild(sun)

        return root
    }

    // MARK: - Avatar

    /// A rider on a bike, assembled from primitives. The entity's -Z axis is
    /// "forward" (RealityKit's look(at:) convention), so parts are laid out
    /// along Z.
    /// REVIEW: replace with a modelled/animated avatar (pedaling legs,
    /// spinning wheels) in the M3 art pass.
    static func makeAvatar() -> Entity {
        let avatar = Entity()

        let frameMaterial = SimpleMaterial(color: .systemRed, isMetallic: false)
        let riderMaterial = SimpleMaterial(color: .systemOrange, isMetallic: false)
        let wheelMaterial = SimpleMaterial(color: NSColor(white: 0.15, alpha: 1), isMetallic: false)

        // Wheels: spheres squashed on X into discs. (generateCylinder is
        // macOS 15+ only and the deployment target is 14, so no cylinders.)
        for zOffset in [Float(-0.55), Float(0.55)] {
            let wheel = ModelEntity(
                mesh: .generateSphere(radius: 0.34),
                materials: [wheelMaterial]
            )
            wheel.scale = SIMD3(0.12, 1, 1)
            wheel.position = SIMD3(0, 0.34, zOffset)
            avatar.addChild(wheel)
        }

        // Frame: a slim box between the wheels.
        let frame = ModelEntity(
            mesh: .generateBox(size: SIMD3<Float>(0.08, 0.5, 1.1), cornerRadius: 0.03),
            materials: [frameMaterial]
        )
        frame.position = SIMD3(0, 0.55, 0)
        avatar.addChild(frame)

        // Rider: torso leaning forward plus a head sphere.
        let torso = ModelEntity(
            mesh: .generateBox(size: SIMD3<Float>(0.3, 0.7, 0.3), cornerRadius: 0.08),
            materials: [riderMaterial]
        )
        torso.position = SIMD3(0, 1.15, 0.05)
        torso.orientation = simd_quatf(angle: -.pi / 7, axis: SIMD3(1, 0, 0)) // lean toward the bars
        avatar.addChild(torso)

        let head = ModelEntity(
            mesh: .generateSphere(radius: 0.13),
            materials: [riderMaterial]
        )
        head.position = SIMD3(0, 1.6, -0.15)
        avatar.addChild(head)

        return avatar
    }

    // MARK: - Scenery

    /// Low-poly trees (cylinder trunk + cone crown) placed deterministically
    /// along the road, alternating sides. Deterministic (no randomness) so
    /// every run and every test sees the same world.
    private static func makeTrees(layout: TrackLayout) -> Entity {
        let container = Entity()
        let trunkMaterial = SimpleMaterial(color: trunkColor, isMetallic: false)
        let crownMaterial = SimpleMaterial(color: crownColor, isMetallic: false)

        // One tree every ~140 m; cheap enough (~60 entities) and enough to
        // give the rider a sense of speed. REVIEW: density and placement.
        let spacing = 140.0
        var index = 0
        var distance = 0.0
        while distance < layout.route.lengthMeters {
            let side: Float = index % 2 == 0 ? 1 : -1
            let lateralOffset = side * Float(10 + (index * 7) % 12) // 10–21 m off the road
            let center = layout.position(atMeters: distance)
            let tangent = layout.tangent(atMeters: distance)
            let sideDir = simd_normalize(simd_cross(SIMD3<Float>(0, 1, 0), tangent))

            // Box trunk + squashed-sphere crown: generateCylinder/generateCone
            // are macOS 15+ only, and the deployment target is macOS 14.
            let tree = Entity()
            let trunk = ModelEntity(
                mesh: .generateBox(size: SIMD3<Float>(0.35, 2.2, 0.35)),
                materials: [trunkMaterial]
            )
            trunk.position.y = 1.1
            tree.addChild(trunk)

            let crown = ModelEntity(
                mesh: .generateSphere(radius: 1.5),
                materials: [crownMaterial]
            )
            crown.scale = SIMD3(1, 1.3, 1)
            crown.position.y = 3.3
            tree.addChild(crown)

            // Drop the tree on the grass ribbon, slightly below road level.
            tree.position = center + sideDir * lateralOffset + SIMD3(0, -0.5, 0)
            container.addChild(tree)

            index += 1
            distance += spacing
        }
        return container
    }

    // MARK: - Mesh generation

    /// A closed strip of triangles following the track: two vertices per
    /// sample, faces emitted in both windings so the strip is visible from
    /// every side (winding mistakes can't blank the road).
    private static func ribbon(
        layout: TrackLayout,
        halfWidth: Float,
        yOffset: Float,
        color: NSColor,
        stepMeters: Double = 20
    ) throws -> ModelEntity {
        let sampleCount = max(Int(layout.route.lengthMeters / stepMeters), 3)
        var positions: [SIMD3<Float>] = []
        positions.reserveCapacity(sampleCount * 2)

        for sample in 0..<sampleCount {
            let distance = layout.route.lengthMeters * Double(sample) / Double(sampleCount)
            let center = layout.position(atMeters: distance) + SIMD3(0, yOffset, 0)
            let tangent = layout.tangent(atMeters: distance)
            let side = simd_normalize(simd_cross(SIMD3<Float>(0, 1, 0), tangent))
            positions.append(center + side * halfWidth)
            positions.append(center - side * halfWidth)
        }

        var indices: [UInt32] = []
        indices.reserveCapacity(sampleCount * 12)
        for sample in 0..<sampleCount {
            let a = UInt32(sample * 2)
            let b = a + 1
            let c = UInt32(((sample + 1) % sampleCount) * 2) // wraps to close the loop
            let d = c + 1
            indices.append(contentsOf: [a, c, b, b, c, d])
            indices.append(contentsOf: [b, c, a, d, c, b]) // reverse winding
        }

        var descriptor = MeshDescriptor(name: "ribbon")
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.primitives = .triangles(indices)
        let mesh = try MeshResource.generate(from: [descriptor])
        return ModelEntity(mesh: mesh, materials: [SimpleMaterial(color: color, isMetallic: false)])
    }
}
