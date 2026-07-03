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

        // Game-feel layers, in rough draw order (see docs/playable-map.md).
        root.addChild(try dashedCenterLine(layout: layout))
        root.addChild(startFinishArch(layout: layout))
        root.addChild(kilometerMarkers(layout: layout))
        root.addChild(startVillage(layout: layout))
        root.addChild(centralMountain(layout: layout))
        root.addChild(rocks(layout: layout))
        root.addChild(makeTrees(layout: layout))

        let sun = DirectionalLight()
        sun.light.intensity = 6000
        sun.look(at: SIMD3(0, 0, 0), from: SIMD3(1500, 2500, 1000), relativeTo: nil)
        root.addChild(sun)

        return root
    }

    // MARK: - Road furniture

    /// Dashed white center line as ONE merged mesh (3 m dashes every 12 m,
    /// ~680 of them): one draw call instead of hundreds of entities, and the
    /// strongest speed cue in the whole scene.
    private static func dashedCenterLine(layout: TrackLayout) throws -> ModelEntity {
        let dashLength = 3.0
        let period = 12.0
        let halfWidth: Float = 0.18
        let lift: Float = 0.05 // above the road, avoids z-fighting

        var positions: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        var distance = 0.0
        while distance + dashLength < layout.route.lengthMeters {
            for endpoint in [distance, distance + dashLength] {
                let center = layout.position(atMeters: endpoint) + SIMD3(0, lift, 0)
                let tangent = layout.tangent(atMeters: endpoint)
                let side = simd_normalize(simd_cross(SIMD3<Float>(0, 1, 0), tangent))
                positions.append(center + side * halfWidth)
                positions.append(center - side * halfWidth)
            }
            let base = UInt32(positions.count - 4)
            let (a, b, c, d) = (base, base + 1, base + 2, base + 3)
            indices.append(contentsOf: [a, c, b, b, c, d])
            indices.append(contentsOf: [b, c, a, d, c, b]) // both windings
            distance += period
        }

        var descriptor = MeshDescriptor(name: "centerline")
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.primitives = .triangles(indices)
        let mesh = try MeshResource.generate(from: [descriptor])
        return ModelEntity(mesh: mesh, materials: [SimpleMaterial(color: .white, isMetallic: false)])
    }

    /// Start/finish arch at km 0: red pillars + white crossbar spanning the
    /// road. Doubles as the lap landmark.
    private static func startFinishArch(layout: TrackLayout) -> Entity {
        let arch = Entity()
        let center = layout.position(atMeters: 0)
        let tangent = layout.tangent(atMeters: 0)
        let side = simd_normalize(simd_cross(SIMD3<Float>(0, 1, 0), tangent))

        let pillarMaterial = SimpleMaterial(color: .systemRed, isMetallic: false)
        for lateral in [Float(-5.5), Float(5.5)] {
            let pillar = ModelEntity(
                mesh: .generateBox(size: SIMD3<Float>(0.6, 6, 0.6)),
                materials: [pillarMaterial]
            )
            pillar.position = center + side * lateral + SIMD3(0, 3, 0)
            arch.addChild(pillar)
        }

        let crossbar = ModelEntity(
            mesh: .generateBox(size: SIMD3<Float>(11.6, 1, 0.8)),
            materials: [SimpleMaterial(color: .white, isMetallic: false)]
        )
        crossbar.position = center + SIMD3(0, 6, 0)
        // The bar's long axis (X) must lie across the road, i.e. along `side`.
        crossbar.orientation = simd_quatf(from: SIMD3(1, 0, 0), to: side)
        arch.addChild(crossbar)
        return arch
    }

    /// Small roadside sign at every kilometer (pole + white plate).
    private static func kilometerMarkers(layout: TrackLayout) -> Entity {
        let container = Entity()
        let poleMaterial = SimpleMaterial(color: NSColor(white: 0.25, alpha: 1), isMetallic: false)
        let plateMaterial = SimpleMaterial(color: .white, isMetallic: false)

        var km = 1000.0
        while km < layout.route.lengthMeters {
            let center = layout.position(atMeters: km)
            let tangent = layout.tangent(atMeters: km)
            let side = simd_normalize(simd_cross(SIMD3<Float>(0, 1, 0), tangent))

            let marker = Entity()
            let pole = ModelEntity(mesh: .generateBox(size: SIMD3<Float>(0.12, 1.6, 0.12)), materials: [poleMaterial])
            pole.position.y = 0.8
            marker.addChild(pole)
            let plate = ModelEntity(mesh: .generateBox(size: SIMD3<Float>(0.9, 0.55, 0.06)), materials: [plateMaterial])
            plate.position.y = 1.75
            // Face the plate toward the road so approaching riders see it.
            plate.orientation = simd_quatf(from: SIMD3(0, 0, 1), to: side)
            marker.addChild(plate)

            marker.position = center + side * 6.5
            container.addChild(marker)
            km += 1000
        }
        return container
    }

    // MARK: - Landmarks

    /// A handful of primitive houses by the start so laps begin *somewhere*.
    /// Diamond roofs are boxes rotated 45° — no cone/pyramid on macOS 14.
    private static func startVillage(layout: TrackLayout) -> Entity {
        let village = Entity()
        let wallColors = [
            NSColor(red: 0.93, green: 0.9, blue: 0.82, alpha: 1),  // cream
            NSColor(red: 0.85, green: 0.6, blue: 0.45, alpha: 1),  // terracotta
            NSColor(red: 0.75, green: 0.82, blue: 0.88, alpha: 1), // pale blue
        ]
        let roofMaterial = SimpleMaterial(color: NSColor(red: 0.55, green: 0.25, blue: 0.2, alpha: 1), isMetallic: false)

        for index in 0..<5 {
            let distance = 60.0 + Double(index) * 45
            let sideSign: Float = index % 2 == 0 ? 1 : -1
            let center = layout.position(atMeters: distance)
            let tangent = layout.tangent(atMeters: distance)
            let side = simd_normalize(simd_cross(SIMD3<Float>(0, 1, 0), tangent))

            let house = Entity()
            let body = ModelEntity(
                mesh: .generateBox(size: SIMD3<Float>(6, 4, 5)),
                materials: [SimpleMaterial(color: wallColors[index % wallColors.count], isMetallic: false)]
            )
            body.position.y = 2
            house.addChild(body)

            let roof = ModelEntity(mesh: .generateBox(size: SIMD3<Float>(4.6, 4.6, 5.4)), materials: [roofMaterial])
            roof.position.y = 4.4
            roof.orientation = simd_quatf(angle: .pi / 4, axis: SIMD3(0, 0, 1)) // diamond profile
            house.addChild(roof)

            house.position = center + side * (sideSign * Float(16 + index * 3)) + SIMD3(0, -0.5, 0)
            village.addChild(house)
        }
        return village
    }

    /// A big squashed sphere rising inside the loop, so the climb visibly
    /// goes *around a mountain* and the horizon isn't empty.
    private static func centralMountain(layout: TrackLayout) -> ModelEntity {
        // Center of the loop = average of track positions.
        var sum = SIMD3<Float>(0, 0, 0)
        let samples = 64
        for sample in 0..<samples {
            let d = layout.route.lengthMeters * Double(sample) / Double(samples)
            sum += layout.position(atMeters: d)
        }
        let center = sum / Float(samples)

        let mountain = ModelEntity(
            mesh: .generateSphere(radius: 300),
            materials: [SimpleMaterial(color: NSColor(red: 0.45, green: 0.5, blue: 0.42, alpha: 1), isMetallic: false)]
        )
        mountain.scale = SIMD3(1, 0.55, 1) // peak ≈ 165 m, above the road's 110 m
        mountain.position = SIMD3(center.x, 0, center.z)
        return mountain
    }

    /// Deterministic rock scatter on the grass, for texture between trees.
    private static func rocks(layout: TrackLayout) -> Entity {
        let container = Entity()
        let material = SimpleMaterial(color: NSColor(white: 0.55, alpha: 1), isMetallic: false)
        for index in 0..<24 {
            let distance = Double(index) * 331.0
            let sideSign: Float = index % 2 == 0 ? 1 : -1
            let center = layout.position(atMeters: distance)
            let tangent = layout.tangent(atMeters: distance)
            let side = simd_normalize(simd_cross(SIMD3<Float>(0, 1, 0), tangent))

            let rock = ModelEntity(
                mesh: .generateSphere(radius: 0.8 + Float(index % 3) * 0.5),
                materials: [material]
            )
            rock.scale = SIMD3(1, 0.55, 1)
            rock.position = center + side * (sideSign * Float(24 + (index * 13) % 18)) + SIMD3(0, -0.6, 0)
            container.addChild(rock)
        }
        return container
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

            // Vary the size deterministically so the forest doesn't look
            // copy-pasted; drop on the grass ribbon, slightly below the road.
            let scale = 0.8 + Float((index * 5) % 7) / 10
            tree.scale = SIMD3(repeating: scale)
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
