import AppKit
import RealityKit
import SkiftKit

/// Deterministic Mediterranean scenery in the ride-camera band beside the road.
/// Geometry is merged by material, keeping the entire pass to ten draw entities.
enum RoadsideDressing {
    private static let groundDrop: Float = 0.72
    private static let villageZoneEnd = 390.0
    private static let vialeRange = 980.0...1_120.0
    private static let vineyardStarts = [1_800.0, 5_600.0]

    static func make(layout: TrackLayout) throws -> Entity {
        var trunks = MeshBatch()
        var darkGreen = MeshBatch()
        var olive = MeshBatch()
        var scrub = MeshBatch()
        var stone = MeshBatch()
        var posts = MeshBatch()
        var vines = MeshBatch()
        var agaves = MeshBatch()
        var redFlowers = MeshBatch()
        var ochreFlowers = MeshBatch()

        addLandscapeClusters(
            layout: layout, trunks: &trunks, darkGreen: &darkGreen,
            olive: &olive, scrub: &scrub, stone: &stone,
            agaves: &agaves, redFlowers: &redFlowers, ochreFlowers: &ochreFlowers
        )
        addViale(layout: layout, trunks: &trunks, darkGreen: &darkGreen, stone: &stone)
        addRoadFurniture(
            layout: layout, trunks: &trunks, darkGreen: &darkGreen, scrub: &scrub,
            stone: &stone, posts: &posts, vines: &vines
        )

        let root = Entity()
        try root.add(trunks, named: "roadside-trunks", color: WorldPalette.trunk)
        try root.add(darkGreen, named: "roadside-cypress", color: WorldPalette.cypress)
        try root.add(olive, named: "roadside-olive", color: WorldPalette.olive)
        try root.add(scrub, named: "roadside-scrub", color: WorldPalette.bushLight)
        try root.add(stone, named: "roadside-stone", color: WorldPalette.rock)
        try root.add(posts, named: "roadside-posts", color: WorldPalette.post)
        try root.add(vines, named: "roadside-vines", color: WorldPalette.vine)
        try root.add(agaves, named: "roadside-agaves", color: WorldPalette.agave)
        try root.add(redFlowers, named: "roadside-red-flowers", color: WorldPalette.flowerRed)
        try root.add(ochreFlowers, named: "roadside-ochre-flowers", color: WorldPalette.flowerOchre)
        return root
    }

    // MARK: - Cluster composition

    private static func addLandscapeClusters(
        layout: TrackLayout,
        trunks: inout MeshBatch,
        darkGreen: inout MeshBatch,
        olive: inout MeshBatch,
        scrub: inout MeshBatch,
        stone: inout MeshBatch,
        agaves: inout MeshBatch,
        redFlowers: inout MeshBatch,
        ochreFlowers: inout MeshBatch
    ) {
        var cluster = 0
        var distance = villageZoneEnd + 90
        while distance < layout.route.lengthMeters {
            defer { cluster += 1; distance += cluster % 3 == 0 ? 190 : 150 }
            guard !vialeRange.contains(distance), !inVineyard(distance) else { continue }

            // Every fifth interval is deliberately calmer so the island
            // breathes — calmer, not empty: bare stretches read as unfinished.
            let quiet = cluster % 5 == 4
            let primarySide: Float = cluster % 4 < 2 ? 1 : -1
            let treeCount = quiet ? 3 : 6 + Int(hash(cluster * 19) * 4)
            for item in 0..<treeCount {
                // Every cluster dresses both shoulders of the road, not just
                // the dominant side — a rider glancing either way should see
                // something (second visual pass finding: one-sided clusters
                // left long bare stretches on the "off" shoulder).
                let oppositeAccent = item % 3 == 2
                let sideSign = oppositeAccent ? -primarySide : primarySide
                let along = (hash(cluster * 101 + item * 37) - 0.5) * (quiet ? 70 : 150)
                let lateral = 10.5 + hash(cluster * 71 + item * 29) * 12.5
                let base = groundPoint(
                    layout: layout, distance: distance + Double(along), lateral: sideSign * lateral
                )
                let scale = 0.9 + hash(cluster * 43 + item * 17) * 0.65
                let species = (cluster * 2 + item) % 5
                switch species {
                case 0:
                    addCypress(base: base, scale: scale * 1.12, trunks: &trunks, crowns: &darkGreen)
                case 1, 2:
                    addOlive(base: base, scale: scale, trunks: &trunks, crowns: &olive)
                default:
                    addUmbrellaPine(base: base, scale: scale, trunks: &trunks, crowns: &darkGreen)
                }
            }

            let shrubCount = quiet ? 3 : 9 + cluster % 5
            for item in 0..<shrubCount {
                let sideSign = item % 3 == 2 ? -primarySide : primarySide
                let along = (hash(cluster * 89 + item * 31) - 0.5) * 155
                let lateral = 7.2 + hash(cluster * 53 + item * 23) * 15
                let base = groundPoint(layout: layout, distance: distance + Double(along), lateral: sideSign * lateral)
                let radius = 0.55 + hash(cluster * 41 + item * 13) * 0.7
                addShrub(base: base, radius: radius, seed: cluster * 41 + item * 13, scrub: &scrub)
            }

            if !quiet && cluster % 2 == 0 {
                for item in 0..<4 {
                    let along = (Float(item) - 1.5) * 2.2
                    let base = groundPoint(layout: layout, distance: distance + Double(along),
                                           lateral: primarySide * (8.5 + Float(item % 2) * 1.5))
                    stone.rock(center: base + SIMD3(0, 0.45, 0),
                               radius: SIMD3(0.9 + Float(item) * 0.16, 0.75, 0.8), seed: cluster * 7 + item)
                }
            }

            if cluster % 4 == 1 {
                let base = groundPoint(layout: layout, distance: distance - 38, lateral: -primarySide * 8.5)
                agaves.agave(center: base, scale: 1.2 + hash(cluster) * 0.35)
            }

            if !quiet && cluster % 3 == 2 {
                for item in 0..<10 {
                    let along = (hash(cluster * 47 + item * 17) - 0.5) * 15
                    let lateral = primarySide * (7.4 + hash(cluster * 61 + item * 11) * 3.2)
                    let base = groundPoint(layout: layout, distance: distance + Double(along), lateral: lateral)
                    if item % 2 == 0 {
                        redFlowers.flower(center: base + SIMD3(0, 0.17, 0), radius: 0.18)
                    } else {
                        ochreFlowers.flower(center: base + SIMD3(0, 0.15, 0), radius: 0.16)
                    }
                }
            }
        }
    }

    private static func addViale(
        layout: TrackLayout,
        trunks: inout MeshBatch,
        darkGreen: inout MeshBatch,
        stone: inout MeshBatch
    ) {
        var distance = vialeRange.lowerBound
        var index = 0
        while distance <= vialeRange.upperBound {
            for side in [Float(-1), Float(1)] {
                let stagger = side > 0 ? 4.0 : 0
                let base = groundPoint(layout: layout, distance: distance + stagger, lateral: side * 9.2)
                addCypress(base: base, scale: 1.42 + Float(index % 3) * 0.08,
                           trunks: &trunks, crowns: &darkGreen)
            }
            index += 1
            distance += 24
        }

        // Low gateway stones make the landmark read before individual trees do.
        for side in [Float(-1), Float(1)] {
            let base = groundPoint(layout: layout, distance: vialeRange.lowerBound - 8, lateral: side * 7.2)
            stone.box(center: base + SIMD3(0, 0.8, 0), size: SIMD3(1.5, 1.6, 1.5))
        }
    }

    private static func addRoadFurniture(
        layout: TrackLayout,
        trunks: inout MeshBatch,
        darkGreen: inout MeshBatch,
        scrub: inout MeshBatch,
        stone: inout MeshBatch,
        posts: inout MeshBatch,
        vines: inout MeshBatch
    ) {
        let walls: [(Double, Double, Float)] = [
            (445, 515, 1), (1_310, 1_385, -1), (2_620, 2_675, 1),
            (3_920, 3_985, -1), (5_220, 5_300, 1), (6_720, 6_780, -1),
        ]
        for (start, end, side) in walls where start < layout.route.lengthMeters {
            addRoadStrip(layout: layout, from: start, to: min(end, layout.route.lengthMeters),
                         lateral: side * 6.35, halfWidth: 0.20, height: 0.48,
                         step: 18, batch: &stone)
        }

        // Village fence: slimmer posts with two long rails, not repeated blocks.
        for side in [Float(-1), Float(1)] {
            var distance = 250.0
            while distance <= 380 {
                let base = groundPoint(layout: layout, distance: distance, lateral: side * 6.15)
                posts.box(center: base + SIMD3(0, 0.48, 0), size: SIMD3(0.14, 0.96, 0.14))
                distance += 13
            }
            addRoadStrip(layout: layout, from: 250, to: 380, lateral: side * 6.15,
                         halfWidth: 0.055, height: 0.12, bottom: 0.47,
                         step: 26, batch: &posts)
        }

        for (parcel, start) in vineyardStarts.enumerated() where start < layout.route.lengthMeters {
            let side: Float = parcel % 2 == 0 ? 1 : -1
            for row in 0..<5 {
                addRoadStrip(layout: layout, from: start, to: start + 44,
                             lateral: side * (12 + Float(row) * 2.8), halfWidth: 0.28,
                             height: 0.48, step: 22, batch: &vines)
            }

            // The vineyard rows fill one shoulder; a cypress windbreak with
            // shrubby underplanting keeps the other shoulder from reading
            // as bare (both-sides finding from the second visual pass).
            var windbreak = start - 6.0
            var index = 0
            while windbreak <= start + 50 {
                let base = groundPoint(layout: layout, distance: windbreak, lateral: -side * 9.0)
                addCypress(base: base, scale: 1.05 + Float(index % 2) * 0.1,
                           trunks: &trunks, crowns: &darkGreen)
                let shrubBase = groundPoint(layout: layout, distance: windbreak + 5.5, lateral: -side * 7.4)
                let radius: Float = 0.6 + hash(parcel * 53 + index * 11) * 0.4
                addShrub(base: shrubBase, radius: radius, seed: parcel * 53 + index * 11, scrub: &scrub)
                index += 1
                windbreak += 11
            }
        }
    }

    // MARK: - Plant silhouettes

    private static func addCypress(
        base: SIMD3<Float>, scale: Float,
        trunks: inout MeshBatch, crowns: inout MeshBatch
    ) {
        trunks.box(center: base + SIMD3(0, 1.25 * scale, 0), size: SIMD3(0.28, 2.5, 0.28) * scale)
        crowns.ellipsoid(center: base + SIMD3(0, 4.3 * scale, 0),
                         radius: SIMD3(1.05, 3.4, 1.05) * scale, sides: 7)
    }

    private static func addOlive(
        base: SIMD3<Float>, scale: Float,
        trunks: inout MeshBatch, crowns: inout MeshBatch
    ) {
        trunks.box(center: base + SIMD3(0, 1.25 * scale, 0), size: SIMD3(0.48, 2.5, 0.48) * scale)
        crowns.ellipsoid(center: base + SIMD3(-0.65, 3.2, 0.1) * scale,
                         radius: SIMD3(1.8, 1.3, 1.55) * scale, sides: 7)
        crowns.ellipsoid(center: base + SIMD3(0.8, 3.05, -0.1) * scale,
                         radius: SIMD3(1.55, 1.15, 1.45) * scale, sides: 7)
    }

    /// Three overlapping lobes instead of one symmetric bipyramid: a single
    /// ellipsoid always resolves to a sharp top/bottom apex no matter how
    /// many sides it has, which read as a flat shard pyramid rather than a
    /// bush (second visual pass finding). Offsetting a few smaller lobes
    /// around a shared base breaks that silhouette into a rounded clump,
    /// echoing the two-lobe olive crown.
    private static func addShrub(base: SIMD3<Float>, radius: Float, seed: Int, scrub: inout MeshBatch) {
        let lobes = 3
        for lobe in 0..<lobes {
            let angle = Float(lobe) / Float(lobes) * 2 * .pi + RoadsideDressingHash.value(seed + lobe) * 1.4
            let offset = radius * 0.42
            let center = base + SIMD3(cos(angle) * offset, 0, sin(angle) * offset)
            let lobeRadius = radius * (0.62 + RoadsideDressingHash.value(seed + lobe * 3) * 0.3)
            scrub.ellipsoid(center: center + SIMD3(0, lobeRadius * 0.68, 0),
                            radius: SIMD3(lobeRadius, lobeRadius * 0.82, lobeRadius), sides: 8)
        }
    }

    private static func addUmbrellaPine(
        base: SIMD3<Float>, scale: Float,
        trunks: inout MeshBatch, crowns: inout MeshBatch
    ) {
        trunks.box(center: base + SIMD3(0, 2.2 * scale, 0), size: SIMD3(0.38, 4.4, 0.38) * scale)
        crowns.ellipsoid(center: base + SIMD3(0, 5.3 * scale, 0),
                         radius: SIMD3(2.8, 1.15, 2.25) * scale, sides: 8)
    }

    // MARK: - Placement

    private static func inVineyard(_ distance: Double) -> Bool {
        vineyardStarts.contains { distance >= $0 - 15 && distance <= $0 + 60 }
    }

    /// The island mesh follows route elevation closely inside this 25 m band.
    /// A 0.72 m drop matches its road-support surface and embeds prop bases.
    private static func groundPoint(layout: TrackLayout, distance: Double, lateral: Float) -> SIMD3<Float> {
        let center = layout.position(atMeters: distance)
        let tangent = layout.tangent(atMeters: distance)
        let side = simd_normalize(simd_cross(SIMD3<Float>(0, 1, 0), tangent))
        return center + side * lateral - SIMD3(0, groundDrop, 0)
    }

    private static func addRoadStrip(
        layout: TrackLayout, from: Double, to: Double, lateral: Float,
        halfWidth: Float, height: Float, bottom: Float = 0,
        step: Double, batch: inout MeshBatch
    ) {
        var distance = from
        while distance < to {
            let end = min(distance + step, to)
            let a = groundPoint(layout: layout, distance: distance, lateral: lateral)
            let b = groundPoint(layout: layout, distance: end, lateral: lateral)
            batch.segmentPrism(from: a, to: b, halfWidth: halfWidth, bottom: bottom, top: bottom + height)
            distance = end
        }
    }

    private static func hash(_ value: Int) -> Float {
        var x = UInt32(truncatingIfNeeded: value &* 747_796_405 &+ 2_891_336_453)
        x = ((x >> ((x >> 28) + 4)) ^ x) &* 277_803_737
        x = (x >> 22) ^ x
        return Float(x & 0x00FF_FFFF) / Float(0x0100_0000)
    }
}

// MARK: - Merged geometry

private struct MeshBatch {
    var positions: [SIMD3<Float>] = []
    var normals: [SIMD3<Float>] = []
    var indices: [UInt32] = []

    mutating func triangle(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>) {
        let cross = simd_cross(b - a, c - a)
        let normal = simd_length_squared(cross) > 0.0001 ? simd_normalize(cross) : SIMD3<Float>(0, 1, 0)
        let base = UInt32(positions.count)
        positions.append(contentsOf: [a, b, c])
        normals.append(contentsOf: [normal, normal, normal])
        indices.append(contentsOf: [base, base + 1, base + 2])
    }

    mutating func quad(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>, _ d: SIMD3<Float>) {
        triangle(a, b, c)
        triangle(a, c, d)
    }

    mutating func box(center: SIMD3<Float>, size: SIMD3<Float>) {
        let h = size * 0.5
        let p = [
            center + SIMD3(-h.x, -h.y, -h.z), center + SIMD3(h.x, -h.y, -h.z),
            center + SIMD3(h.x, h.y, -h.z), center + SIMD3(-h.x, h.y, -h.z),
            center + SIMD3(-h.x, -h.y, h.z), center + SIMD3(h.x, -h.y, h.z),
            center + SIMD3(h.x, h.y, h.z), center + SIMD3(-h.x, h.y, h.z),
        ]
        quad(p[0], p[1], p[2], p[3]); quad(p[5], p[4], p[7], p[6])
        quad(p[4], p[0], p[3], p[7]); quad(p[1], p[5], p[6], p[2])
        quad(p[3], p[2], p[6], p[7]); quad(p[4], p[5], p[1], p[0])
    }

    mutating func segmentPrism(
        from a: SIMD3<Float>, to b: SIMD3<Float>, halfWidth: Float, bottom: Float, top: Float
    ) {
        let direction = simd_normalize(SIMD3<Float>(b.x - a.x, 0, b.z - a.z))
        let side = SIMD3<Float>(-direction.z, 0, direction.x) * halfWidth
        let upBottom = SIMD3<Float>(0, bottom, 0)
        let upTop = SIMD3<Float>(0, top, 0)
        let p0 = a + side + upBottom, p1 = a - side + upBottom
        let p2 = b + side + upBottom, p3 = b - side + upBottom
        let p4 = a + side + upTop, p5 = a - side + upTop
        let p6 = b + side + upTop, p7 = b - side + upTop
        quad(p0, p2, p6, p4); quad(p3, p1, p5, p7)
        quad(p1, p0, p4, p5); quad(p2, p3, p7, p6)
        quad(p4, p6, p7, p5); quad(p1, p3, p2, p0)
    }

    mutating func ellipsoid(center: SIMD3<Float>, radius: SIMD3<Float>, sides: Int) {
        let top = center + SIMD3(0, radius.y, 0)
        let bottom = center - SIMD3(0, radius.y, 0)
        for index in 0..<sides {
            let a = Float(index) / Float(sides) * 2 * .pi
            let b = Float(index + 1) / Float(sides) * 2 * .pi
            let p0 = center + SIMD3(cos(a) * radius.x, 0, sin(a) * radius.z)
            let p1 = center + SIMD3(cos(b) * radius.x, 0, sin(b) * radius.z)
            triangle(top, p0, p1); triangle(bottom, p1, p0)
        }
    }

    mutating func rock(center: SIMD3<Float>, radius: SIMD3<Float>, seed: Int) {
        let sides = 6
        let top = center + SIMD3(0, radius.y, 0)
        for index in 0..<sides {
            let a = Float(index) / Float(sides) * 2 * .pi
            let b = Float(index + 1) / Float(sides) * 2 * .pi
            let wa = 0.78 + RoadsideDressingHash.value(seed + index) * 0.32
            let wb = 0.78 + RoadsideDressingHash.value(seed + index + 1) * 0.32
            let p0 = center + SIMD3(cos(a) * radius.x * wa, -radius.y * 0.5, sin(a) * radius.z * wa)
            let p1 = center + SIMD3(cos(b) * radius.x * wb, -radius.y * 0.5, sin(b) * radius.z * wb)
            triangle(top, p0, p1)
        }
    }

    mutating func flower(center: SIMD3<Float>, radius: Float) {
        let east = center + SIMD3(radius, 0, 0), west = center - SIMD3(radius, 0, 0)
        let north = center + SIMD3(0, 0, radius), south = center - SIMD3(0, 0, radius)
        let top = center + SIMD3(0, radius, 0), bottom = center - SIMD3(0, radius * 0.55, 0)
        triangle(top, east, north); triangle(top, north, west)
        triangle(top, west, south); triangle(top, south, east)
        triangle(bottom, north, east); triangle(bottom, west, north)
        triangle(bottom, south, west); triangle(bottom, east, south)
    }

    mutating func agave(center: SIMD3<Float>, scale: Float) {
        for leaf in 0..<7 {
            let angle = Float(leaf) / 7 * 2 * .pi
            let side = SIMD3<Float>(cos(angle), 0, sin(angle))
            let across = SIMD3<Float>(-side.z, 0, side.x) * 0.16 * scale
            let rootA = center + across, rootB = center - across
            let tip = center + side * 1.15 * scale + SIMD3(0, 0.62 * scale, 0)
            triangle(rootA, rootB, tip)
            triangle(rootB, rootA, tip)
        }
    }

    func mesh(named name: String) throws -> MeshResource {
        var descriptor = MeshDescriptor(name: name)
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.normals = MeshBuffers.Normals(normals)
        descriptor.primitives = .triangles(indices)
        return try MeshResource.generate(from: [descriptor])
    }
}

private enum RoadsideDressingHash {
    static func value(_ value: Int) -> Float {
        var x = UInt32(truncatingIfNeeded: value &* 747_796_405 &+ 2_891_336_453)
        x = ((x >> ((x >> 28) + 4)) ^ x) &* 277_803_737
        x = (x >> 22) ^ x
        return Float(x & 0x00FF_FFFF) / Float(0x0100_0000)
    }
}

private extension Entity {
    func add(_ batch: MeshBatch, named name: String, color: NSColor) throws {
        guard !batch.indices.isEmpty else { return }
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: color)
        material.roughness = .init(floatLiteral: 1)
        material.metallic = .init(floatLiteral: 0)
        addChild(ModelEntity(mesh: try batch.mesh(named: name), materials: [material]))
    }
}
