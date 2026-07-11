import AppKit
import RealityKit
import SkiftKit

/// Builds the procedural 3D world from a track layout: continuous island,
/// road, water, landmarks, vegetation and atmosphere.
///
enum WorldBuilder {

    // MARK: - World

    static func makeWorld(layout: TrackLayout) throws -> Entity {
        let root = Entity()

        // Sea level is y = 0; the route's lowest elevation is ~10 m, so the
        // island always sits above the water.
        let water = ModelEntity(
            mesh: .generatePlane(width: 8000, depth: 8000),
            materials: [matteMaterial(WorldPalette.water)]
        )
        root.addChild(water)

        let terrain = ModelEntity(
            mesh: try IslandTerrainBuilder.makeMesh(layout: layout),
            materials: [matteMaterial(WorldPalette.grass)]
        )
        root.addChild(terrain)

        // A narrow sun-baked shoulder separates asphalt from vegetation.
        root.addChild(try ribbon(layout: layout, halfWidth: 5.4, yOffset: -0.18, color: WorldPalette.sand))
        root.addChild(try ribbon(layout: layout, halfWidth: 4, yOffset: 0, color: WorldPalette.road))

        // Game-feel layers, in rough draw order (see docs/playable-map.md).
        root.addChild(try dashedCenterLine(layout: layout))
        root.addChild(startFinishArch(layout: layout))
        root.addChild(kilometerMarkers(layout: layout))
        root.addChild(startVillage(layout: layout))
        root.addChild(centralMountain(layout: layout))
        root.addChild(try distantHorizon(layout: layout))
        root.addChild(rocks(layout: layout))
        root.addChild(makeTrees(layout: layout))

        let sun = DirectionalLight()
        sun.light.color = WorldPalette.sun
        // Keep primitive materials matte-looking: high intensities create
        // plastic white hotspots before the PBR material pass lands.
        sun.light.intensity = 3_200
        sun.look(at: SIMD3(0, 0, 0), from: SIMD3(-1800, 1400, 900), relativeTo: nil)
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
        return ModelEntity(mesh: mesh, materials: [matteMaterial(WorldPalette.roadMarking)])
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
            WorldPalette.villageWall,
            NSColor(red: 0.72, green: 0.52, blue: 0.37, alpha: 1),
            NSColor(red: 0.64, green: 0.70, blue: 0.69, alpha: 1),
        ]
        let roofMaterial = matteMaterial(WorldPalette.terracotta)

        for index in 0..<5 {
            let distance = 60.0 + Double(index) * 45
            let sideSign: Float = index % 2 == 0 ? 1 : -1
            let center = layout.position(atMeters: distance)
            let tangent = layout.tangent(atMeters: distance)
            let side = simd_normalize(simd_cross(SIMD3<Float>(0, 1, 0), tangent))

            let house = Entity()
            let body = ModelEntity(
                mesh: .generateBox(size: SIMD3<Float>(6, 4, 5)),
                materials: [matteMaterial(wallColors[index % wallColors.count])]
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
            materials: [matteMaterial(WorldPalette.mountain)]
        )
        mountain.scale = SIMD3(1, 0.55, 1) // peak ≈ 165 m, above the road's 110 m
        mountain.position = SIMD3(center.x, 0, center.z)
        return mountain
    }

    /// Faceted silhouettes beyond the island create aerial perspective and
    /// prevent the sea from ending at an empty, perfectly flat horizon.
    private static func distantHorizon(layout: TrackLayout) throws -> Entity {
        let container = Entity()
        let center = trackCenter(layout: layout)
        let islandRadius = trackRadius(layout: layout, around: center)
        let material = matteMaterial(WorldPalette.distantMountain)

        for index in 0..<9 {
            let angle = Float(index) / 9 * 2 * .pi
            let radius = islandRadius + Float(1_500 + (index % 3) * 220)
            let width = Float(320 + (index * 37) % 180)
            let height = Float(120 + (index * 41) % 110)
            let mountain = ModelEntity(
                mesh: try facetedMountainMesh(radius: width, height: height, seed: index),
                materials: [material]
            )
            mountain.position = SIMD3(
                center.x + cos(angle) * radius,
                -18,
                center.z + sin(angle) * radius
            )
            mountain.orientation = simd_quatf(angle: -angle, axis: SIMD3(0, 1, 0))
            container.addChild(mountain)
        }
        return container
    }

    private static func trackCenter(layout: TrackLayout) -> SIMD3<Float> {
        var sum = SIMD3<Float>(repeating: 0)
        let samples = 64
        for sample in 0..<samples {
            let distance = layout.route.lengthMeters * Double(sample) / Double(samples)
            sum += layout.position(atMeters: distance)
        }
        return sum / Float(samples)
    }

    private static func trackRadius(layout: TrackLayout, around center: SIMD3<Float>) -> Float {
        var radius: Float = 0
        let samples = 128
        for sample in 0..<samples {
            let distance = layout.route.lengthMeters * Double(sample) / Double(samples)
            let position = layout.position(atMeters: distance)
            radius = max(radius, simd_length(SIMD2(position.x - center.x, position.z - center.z)))
        }
        return radius
    }

    /// A deliberately coarse asymmetric mountain: one uneven base ring, one
    /// shoulder ring and an offset peak. Twelve sides keep facets visible.
    private static func facetedMountainMesh(radius: Float, height: Float, seed: Int) throws -> MeshResource {
        let segments = 12
        var positions: [SIMD3<Float>] = []
        positions.reserveCapacity(segments * 2 + 1)

        for ring in 0..<2 {
            let ringRadius = ring == 0 ? radius : radius * 0.48
            let y = ring == 0 ? Float(0) : height * 0.48
            for segment in 0..<segments {
                let angle = Float(segment) / Float(segments) * 2 * .pi
                let variation = 0.82 + Float((segment * 17 + seed * 11) % 29) / 100
                positions.append(SIMD3(cos(angle) * ringRadius * variation, y, sin(angle) * ringRadius * variation))
            }
        }
        positions.append(SIMD3(radius * 0.09, height, -radius * 0.06))

        var indices: [UInt32] = []
        for segment in 0..<segments {
            let next = (segment + 1) % segments
            let a = UInt32(segment)
            let b = UInt32(next)
            let c = UInt32(segments + segment)
            let d = UInt32(segments + next)
            indices.append(contentsOf: [a, c, b, b, c, d])
            indices.append(contentsOf: [b, c, a, d, c, b])

            let peak = UInt32(segments * 2)
            indices.append(contentsOf: [c, peak, d, d, peak, c])
        }

        var descriptor = MeshDescriptor(name: "distant-mountain")
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.primitives = .triangles(indices)
        return try MeshResource.generate(from: [descriptor])
    }

    /// Deterministic rock scatter on the grass, for texture between trees.
    private static func rocks(layout: TrackLayout) -> Entity {
        let container = Entity()
        let material = matteMaterial(WorldPalette.rock)
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
    /// The avatar plus references to its animated parts. `RideSceneView`
    /// spins the wheels with speed and orbits the pedals with cadence in its
    /// per-frame update.
    struct AvatarRig {
        let root: Entity
        let wheels: [ModelEntity]
        let pedals: [ModelEntity]
        /// Crank axle in avatar-local coordinates; pedals orbit this point.
        static let crankCenter = SIMD3<Float>(0, 0.45, 0.05)
        static let crankRadius: Float = 0.17
        static let wheelRadius: Float = 0.34
    }

    static func makeAvatar() -> AvatarRig {
        let avatar = Entity()
        var wheels: [ModelEntity] = []
        var pedals: [ModelEntity] = []

        let frameMaterial = SimpleMaterial(color: NSColor(white: 0.12, alpha: 1), isMetallic: false)
        let riderMaterial = SimpleMaterial(color: WorldPalette.riderOrange, isMetallic: false)
        let wheelMaterial = SimpleMaterial(color: NSColor(white: 0.15, alpha: 1), isMetallic: false)

        // Wheels: spheres squashed on X into discs. (generateCylinder is
        // macOS 15+ only and the deployment target is 14, so no cylinders.)
        // A white rim marker makes the spin visible on flat-shaded geometry.
        for zOffset in [Float(-0.55), Float(0.55)] {
            let wheel = ModelEntity(
                mesh: .generateSphere(radius: AvatarRig.wheelRadius),
                materials: [wheelMaterial]
            )
            wheel.scale = SIMD3(0.12, 1, 1)
            wheel.position = SIMD3(0, AvatarRig.wheelRadius, zOffset)
            let marker = ModelEntity(
                mesh: .generateBox(size: SIMD3<Float>(0.6, 0.07, 0.07)),
                materials: [SimpleMaterial(color: .white, isMetallic: false)]
            )
            marker.position = SIMD3(0, 0.24, 0)
            wheel.addChild(marker)
            avatar.addChild(wheel)
            wheels.append(wheel)
        }

        // Pedals: two boxes orbiting the crank in opposite phase — the
        // per-frame update sets their position from the cadence angle.
        let pedalMaterial = SimpleMaterial(color: NSColor(white: 0.1, alpha: 1), isMetallic: false)
        for lateral in [Float(-0.18), Float(0.18)] {
            let pedal = ModelEntity(
                mesh: .generateBox(size: SIMD3<Float>(0.16, 0.07, 0.24)),
                materials: [pedalMaterial]
            )
            pedal.position = AvatarRig.crankCenter + SIMD3(lateral, -AvatarRig.crankRadius, 0)
            avatar.addChild(pedal)
            pedals.append(pedal)
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

        return AvatarRig(root: avatar, wheels: wheels, pedals: pedals)
    }

    // MARK: - Scenery

    /// Low-poly trees (cylinder trunk + cone crown) placed deterministically
    /// along the road, alternating sides. Deterministic (no randomness) so
    /// every run and every test sees the same world.
    private static func makeTrees(layout: TrackLayout) -> Entity {
        let container = Entity()
        let trunkMaterial = matteMaterial(WorldPalette.trunk)
        let crownMaterial = matteMaterial(WorldPalette.crown)

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
        var normals: [SIMD3<Float>] = []
        positions.reserveCapacity(sampleCount * 2)
        normals.reserveCapacity(sampleCount * 2)

        for sample in 0..<sampleCount {
            let distance = layout.route.lengthMeters * Double(sample) / Double(sampleCount)
            let center = layout.position(atMeters: distance) + SIMD3(0, yOffset, 0)
            let tangent = layout.tangent(atMeters: distance)
            let side = simd_normalize(simd_cross(SIMD3<Float>(0, 1, 0), tangent))
            let normal = simd_normalize(simd_cross(tangent, side))
            positions.append(center + side * halfWidth)
            positions.append(center - side * halfWidth)
            normals.append(normal)
            normals.append(normal)
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
        descriptor.normals = MeshBuffers.Normals(normals)
        descriptor.primitives = .triangles(indices)
        let mesh = try MeshResource.generate(from: [descriptor])
        return ModelEntity(mesh: mesh, materials: [matteMaterial(color)])
    }

    /// High roughness removes the plastic highlights produced by
    /// `SimpleMaterial` under the directional sun while preserving broad,
    /// readable low-poly shading.
    private static func matteMaterial(_ color: NSColor) -> PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: color)
        material.roughness = .init(floatLiteral: 0.92)
        material.metallic = .init(floatLiteral: 0)
        return material
    }
}
