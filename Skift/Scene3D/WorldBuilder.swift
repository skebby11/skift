import AppKit
import RealityKit
import SkiftKit

/// Builds the placeholder 3D world from a track layout: water, a green
/// island ribbon, the road, and a sun. All meshes are generated — no assets.
enum WorldBuilder {

    static func makeWorld(layout: TrackLayout) throws -> Entity {
        let root = Entity()

        let water = ModelEntity(
            mesh: .generatePlane(width: 6000, depth: 6000),
            materials: [SimpleMaterial(color: NSColor(red: 0.15, green: 0.4, blue: 0.65, alpha: 1), isMetallic: false)]
        )
        root.addChild(water)

        let island = try ribbon(
            layout: layout,
            halfWidth: 45,
            yOffset: -0.5,
            color: NSColor(red: 0.35, green: 0.6, blue: 0.3, alpha: 1)
        )
        root.addChild(island)

        let road = try ribbon(
            layout: layout,
            halfWidth: 4,
            yOffset: 0,
            color: NSColor(white: 0.35, alpha: 1)
        )
        root.addChild(road)

        let sun = DirectionalLight()
        sun.light.intensity = 6000
        sun.look(at: SIMD3(0, 0, 0), from: SIMD3(1500, 2500, 1000), relativeTo: nil)
        root.addChild(sun)

        return root
    }

    static func makeAvatar() -> Entity {
        let body = ModelEntity(
            mesh: .generateBox(size: SIMD3<Float>(0.5, 1.6, 1.7), cornerRadius: 0.2),
            materials: [SimpleMaterial(color: .systemOrange, isMetallic: false)]
        )
        body.position.y = 0.8
        let avatar = Entity()
        avatar.addChild(body)
        return avatar
    }

    /// A closed strip of triangles following the track: two vertices per
    /// sample, faces emitted in both windings so the strip is visible from
    /// every side.
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
            let c = UInt32(((sample + 1) % sampleCount) * 2)
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
