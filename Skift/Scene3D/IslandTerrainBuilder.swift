import RealityKit
import SkiftKit

/// Generates one continuous, deterministic low-poly island around the route.
enum IslandTerrainBuilder {
    private static let routeSampleCount = 320
    private static let cellSize: Float = 42
    private static let coastalBuffer: Float = 210

    static func makeMesh(layout: TrackLayout) throws -> MeshResource {
        let route = sampleRoute(layout)
        let bounds = expandedBounds(of: route, padding: coastalBuffer)
        let columns = max(Int(ceil((bounds.max.x - bounds.min.x) / cellSize)), 2)
        let rows = max(Int(ceil((bounds.max.y - bounds.min.y) / cellSize)), 2)

        var positions: [SIMD3<Float>] = []
        var isLand: [Bool] = []
        positions.reserveCapacity((columns + 1) * (rows + 1))
        isLand.reserveCapacity((columns + 1) * (rows + 1))

        for row in 0...rows {
            let z = bounds.min.y + Float(row) / Float(rows) * (bounds.max.y - bounds.min.y)
            for column in 0...columns {
                let x = bounds.min.x + Float(column) / Float(columns) * (bounds.max.x - bounds.min.x)
                let point = SIMD2<Float>(x, z)
                let nearest = nearestRouteSample(to: point, route: route)
                let inside = contains(point, polygon: route)
                let localCoast = coastalWidth(at: point)
                let land = inside || nearest.distance <= localCoast
                positions.append(SIMD3(
                    x,
                    terrainHeight(inside: inside, nearest: nearest, point: point, coastalWidth: localCoast),
                    z
                ))
                isLand.append(land)
            }
        }

        func vertex(_ column: Int, _ row: Int) -> Int {
            row * (columns + 1) + column
        }

        var indices: [UInt32] = []
        indices.reserveCapacity(columns * rows * 6)
        for row in 0..<rows {
            for column in 0..<columns {
                let a = vertex(column, row)
                let b = vertex(column + 1, row)
                let c = vertex(column, row + 1)
                let d = vertex(column + 1, row + 1)
                guard isLand[a] || isLand[b] || isLand[c] || isLand[d] else { continue }
                indices.append(contentsOf: [UInt32(a), UInt32(c), UInt32(b)])
                indices.append(contentsOf: [UInt32(b), UInt32(c), UInt32(d)])
            }
        }

        let flat = flatShadedMesh(positions: positions, indices: indices)
        var descriptor = MeshDescriptor(name: "continuous-island")
        descriptor.positions = MeshBuffers.Positions(flat.positions)
        descriptor.normals = MeshBuffers.Normals(flat.normals)
        descriptor.primitives = .triangles(flat.indices)
        return try MeshResource.generate(from: [descriptor])
    }

    private struct NearestSample {
        let position: SIMD3<Float>
        let distance: Float
    }

    private static func sampleRoute(_ layout: TrackLayout) -> [SIMD3<Float>] {
        (0..<routeSampleCount).map { index in
            let distance = layout.route.lengthMeters * Double(index) / Double(routeSampleCount)
            return layout.position(atMeters: distance)
        }
    }

    private static func expandedBounds(
        of route: [SIMD3<Float>],
        padding: Float
    ) -> (min: SIMD2<Float>, max: SIMD2<Float>) {
        var minimum = SIMD2<Float>(repeating: .greatestFiniteMagnitude)
        var maximum = SIMD2<Float>(repeating: -.greatestFiniteMagnitude)
        for sample in route {
            let point = SIMD2(sample.x, sample.z)
            minimum = simd_min(minimum, point)
            maximum = simd_max(maximum, point)
        }
        return (minimum - SIMD2(repeating: padding), maximum + SIMD2(repeating: padding))
    }

    private static func nearestRouteSample(
        to point: SIMD2<Float>,
        route: [SIMD3<Float>]
    ) -> NearestSample {
        var best = route[0]
        var bestSquared = Float.greatestFiniteMagnitude
        for sample in route {
            let delta = point - SIMD2(sample.x, sample.z)
            let squared = simd_length_squared(delta)
            if squared < bestSquared {
                best = sample
                bestSquared = squared
            }
        }
        return NearestSample(position: best, distance: sqrt(bestSquared))
    }

    private static func terrainHeight(
        inside: Bool,
        nearest: NearestSample,
        point: SIMD2<Float>,
        coastalWidth: Float
    ) -> Float {
        let roadMask = smoothstep(edge0: 24, edge1: 170, value: nearest.distance)
        let relief = terrainNoise(at: point) * 11 * roadMask

        if inside {
            // Preserve support directly under the road, then let the interior
            // sit lower so the authored route remains visually dominant.
            let inset = min(nearest.distance, 320) * 0.055
            return max(1.2, nearest.position.y - 0.7 - inset + relief)
        }

        let t = min(max(nearest.distance / coastalWidth, 0), 1)
        let smooth = t * t * (3 - 2 * t)
        return simd_mix(nearest.position.y - 0.8 + relief * (1 - smooth), 0.7, smooth)
    }

    private static func coastalWidth(at point: SIMD2<Float>) -> Float {
        let broad = sin(point.x * 0.0031 + point.y * 0.0017) * 42
        let secondary = cos(point.x * 0.0063 - point.y * 0.0049) * 24
        return coastalBuffer + broad + secondary
    }

    private static func terrainNoise(at point: SIMD2<Float>) -> Float {
        let broad = sin(point.x * 0.0051) * cos(point.y * 0.0043)
        let diagonal = sin((point.x + point.y) * 0.0087) * 0.38
        return broad + diagonal
    }

    private static func smoothstep(edge0: Float, edge1: Float, value: Float) -> Float {
        let t = min(max((value - edge0) / (edge1 - edge0), 0), 1)
        return t * t * (3 - 2 * t)
    }

    /// Even-odd ray casting in XZ. Route samples are already ordered and form
    /// a closed, non-self-intersecting polygon.
    private static func contains(_ point: SIMD2<Float>, polygon: [SIMD3<Float>]) -> Bool {
        var inside = false
        var previous = polygon.count - 1
        for current in polygon.indices {
            let a = SIMD2(polygon[current].x, polygon[current].z)
            let b = SIMD2(polygon[previous].x, polygon[previous].z)
            let crossesY = (a.y > point.y) != (b.y > point.y)
            if crossesY {
                let intersectionX = (b.x - a.x) * (point.y - a.y) / (b.y - a.y) + a.x
                if point.x < intersectionX { inside.toggle() }
            }
            previous = current
        }
        return inside
    }

    private static func flatShadedMesh(
        positions: [SIMD3<Float>],
        indices: [UInt32]
    ) -> (positions: [SIMD3<Float>], normals: [SIMD3<Float>], indices: [UInt32]) {
        var flatPositions: [SIMD3<Float>] = []
        var flatNormals: [SIMD3<Float>] = []
        var flatIndices: [UInt32] = []
        flatPositions.reserveCapacity(indices.count)
        flatNormals.reserveCapacity(indices.count)
        flatIndices.reserveCapacity(indices.count)

        for triangle in stride(from: 0, to: indices.count, by: 3) {
            let a = positions[Int(indices[triangle])]
            let b = positions[Int(indices[triangle + 1])]
            let c = positions[Int(indices[triangle + 2])]
            let cross = simd_cross(b - a, c - a)
            let normal = simd_length_squared(cross) > 0 ? simd_normalize(cross) : SIMD3<Float>(0, 1, 0)
            let base = UInt32(flatPositions.count)
            flatPositions.append(contentsOf: [a, b, c])
            flatNormals.append(contentsOf: [normal, normal, normal])
            flatIndices.append(contentsOf: [base, base + 1, base + 2])
        }
        return (flatPositions, flatNormals, flatIndices)
    }
}
