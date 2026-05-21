import RealityKit
import UIKit

// Builds the immovable structural pieces of the VEX field:
//   • alternating-tile floor + thick collider
//   • perimeter walls + corner posts
//   • central diamond + diagonal stripes
// Everything is added to `fieldContainer`.
enum FieldStructure {

    @MainActor
    static func build(into fieldContainer: Entity,
                      surfaceMaterial: PhysicsMaterialResource) {
        addFloor(into: fieldContainer, surfaceMaterial: surfaceMaterial)
        addWallsAndPosts(into: fieldContainer, surfaceMaterial: surfaceMaterial)
        addCentralDiamond(into: fieldContainer)
        addDiagonalLines(into: fieldContainer)
    }

    // --- FIELD (12' x 12' VEX tiles, alternating gray checkerboard) -------
    @MainActor
    private static func addFloor(into fieldContainer: Entity,
                                 surfaceMaterial: PhysicsMaterialResource) {
        let fieldSize = SimulationConstants.fieldSize
        let floorMesh = MeshResource.generatePlane(width: fieldSize, depth: fieldSize)
        let darkTileMat = SimpleMaterial(color: UIColor(white: 0.32, alpha: 1), isMetallic: false)
        let lightTileMat = SimpleMaterial(color: UIColor(white: 0.36, alpha: 1), isMetallic: false)
        let floorEntity = ModelEntity(mesh: floorMesh, materials: [darkTileMat])

        // Thick floor collider, offset downward so its TOP is flush with the
        // visible plane at y=0. 10 cm thick is plenty for physics to resolve
        // cleanly (the previous 1 cm let pin geometry clip through).
        let floorThickness: Float = 0.1
        let floorShape = ShapeResource.generateBox(size: [fieldSize, floorThickness, fieldSize])
            .offsetBy(translation: SIMD3<Float>(0, -floorThickness / 2, 0))
        floorEntity.components.set(PhysicsBodyComponent(shapes: [floorShape], mass: 0, material: surfaceMaterial, mode: .static))
        floorEntity.components.set(CollisionComponent(shapes: [floorShape]))
        fieldContainer.addChild(floorEntity)

        // 6x6 tile checkerboard overlay (light tiles on top of dark base)
        let floorTileSize = SimulationConstants.tileSize
        let tileMesh = MeshResource.generatePlane(width: floorTileSize, depth: floorTileSize)
        let startOffset = -fieldSize / 2 + floorTileSize / 2

        for i in 0..<6 {
            for j in 0..<6 where (i + j) % 2 == 0 {
                let xPos = startOffset + (Float(i) * floorTileSize)
                let zPos = startOffset + (Float(j) * floorTileSize)
                let tile = ModelEntity()
                tile.model = ModelComponent(mesh: tileMesh, materials: [lightTileMat])
                tile.position = SIMD3<Float>(xPos, 0.001, zPos)
                fieldContainer.addChild(tile)
            }
        }
    }

    // --- PERIMETER WALLS + CORNER POSTS ----------------------------------
    @MainActor
    private static func addWallsAndPosts(into fieldContainer: Entity,
                                         surfaceMaterial: PhysicsMaterialResource) {
        let wallHeight    = SimulationConstants.wallHeight
        let wallThickness = SimulationConstants.wallThickness
        let halfField     = SimulationConstants.halfField
        let fieldSize     = SimulationConstants.fieldSize

        let longSize:  SIMD3<Float> = [fieldSize, wallHeight, wallThickness]
        let shortSize: SIMD3<Float> = [wallThickness, wallHeight, fieldSize]
        let longShape  = ShapeResource.generateBox(size: longSize)
        let shortShape = ShapeResource.generateBox(size: shortSize)
        let longMesh   = MeshResource.generateBox(size: longSize)
        let shortMesh  = MeshResource.generateBox(size: shortSize)
        let wallMaterial = SimpleMaterial(color: .white, isMetallic: false)
        let walls: [(SIMD3<Float>, ShapeResource, MeshResource)] = [
            ([0, wallHeight / 2, -halfField], longShape, longMesh),
            ([0, wallHeight / 2,  halfField], longShape, longMesh),
            ([-halfField, wallHeight / 2, 0], shortShape, shortMesh),
            ([ halfField, wallHeight / 2, 0], shortShape, shortMesh),
        ]
        for (pos, shape, mesh) in walls {
            let wall = ModelEntity(mesh: mesh, materials: [wallMaterial])
            wall.position = pos
            wall.components.set(PhysicsBodyComponent(shapes: [shape], mass: 0, material: surfaceMaterial, mode: .static))
            wall.components.set(CollisionComponent(shapes: [shape]))
            fieldContainer.addChild(wall)
        }

        // Corner posts (dark gray, slightly taller than walls)
        let postSize: SIMD3<Float> = [wallThickness * 1.5, wallHeight * 1.1, wallThickness * 1.5]
        let postMesh = MeshResource.generateBox(size: postSize)
        let postMaterial = SimpleMaterial(color: .darkGray, isMetallic: true)
        for x in [-halfField, halfField] {
            for z in [-halfField, halfField] {
                let post = ModelEntity(mesh: postMesh, materials: [postMaterial])
                post.position = [x, postSize.y / 2, z]
                fieldContainer.addChild(post)
            }
        }
    }

    // --- CENTRAL DIAMOND (Midfield zone — vertices at N/E/S/W of center) -
    @MainActor
    private static func addCentralDiamond(into fieldContainer: Entity) {
        let lineMat = SimpleMaterial(color: .white, isMetallic: false)
        let stripeWidth: Float = 0.025
        let diamondRadius: Float = 0.6
        let dr = diamondRadius

        let sqrtTwo = Float(2.0).squareRoot()
        let diamondSide: Float = diamondRadius * sqrtTwo

        struct DiamondEdgeSpec { let pos: SIMD3<Float>; let angle: Float }

        let diamondEdges: [DiamondEdgeSpec] = [
            DiamondEdgeSpec(pos: SIMD3<Float>( dr / 2, 0.002,  dr / 2), angle: 3 * .pi / 4),
            DiamondEdgeSpec(pos: SIMD3<Float>( dr / 2, 0.002, -dr / 2), angle: .pi / 4),
            DiamondEdgeSpec(pos: SIMD3<Float>(-dr / 2, 0.002, -dr / 2), angle: 3 * .pi / 4),
            DiamondEdgeSpec(pos: SIMD3<Float>(-dr / 2, 0.002,  dr / 2), angle: .pi / 4),
        ]

        for spec in diamondEdges {
            let mesh = MeshResource.generatePlane(width: stripeWidth, depth: diamondSide)
            let edge = ModelEntity()
            edge.model = ModelComponent(mesh: mesh, materials: [lineMat])
            edge.position = spec.pos
            edge.orientation = simd_quatf(angle: spec.angle, axis: SIMD3<Float>(0, 1, 0))
            fieldContainer.addChild(edge)
        }
    }

    // --- DIAGONAL LINES — corner-side → diamond, stopping short of the L tape ---
    // NW-SE diagonal: SINGLE stripe (in 2 segments)
    // NE-SW diagonal: DOUBLE stripe (in 2 segments)
    @MainActor
    private static func addDiagonalLines(into fieldContainer: Entity) {
        let lineMat = SimpleMaterial(color: .white, isMetallic: false)
        let stripeWidth: Float = 0.025
        let diamondRadius: Float = 0.6
        let halfField = SimulationConstants.halfField
        let fieldSize = SimulationConstants.fieldSize
        let sqrtTwo = Float(2.0).squareRoot()

        // The L tape's vertical leg's "inner" end is at |z| = halfField -
        // 0.5 * 1.0225 * tileSize. Stop the diagonal at the matching point
        // on the line z = ±x so it never crosses the L colored lines.
        let diagStopAbs: Float = halfField - 0.5 * 1.03 * (fieldSize / 6)
        let segLength: Float = sqrtTwo * (diagStopAbs - (diamondRadius / 2))
        let segOff: Float = (diagStopAbs + (diamondRadius / 2)) / 2

        // Single-striped NW-SE segments
        let singleSegMids: [SIMD3<Float>] = [
            [-segOff, 0.002,  segOff],   // NW
            [ segOff, 0.002, -segOff],   // SE
        ]
        for mid in singleSegMids {
            let mesh = MeshResource.generatePlane(width: stripeWidth, depth: segLength)
            let strip = ModelEntity(mesh: mesh, materials: [lineMat])
            strip.position = mid
            strip.orientation = simd_quatf(angle: -.pi / 4, axis: [0, 1, 0])
            fieldContainer.addChild(strip)
        }
        // Double-striped NE-SW segments
        let doubleSegMids: [SIMD3<Float>] = [
            [ segOff, 0.002,  segOff],   // NE
            [-segOff, 0.002, -segOff],   // SW
        ]
        let perpNWSE = simd_normalize(SIMD3<Float>(1, 0, -1))   // perpendicular to NE-SW direction
        for mid in doubleSegMids {
            for stripeOff: Float in [-0.025, 0.025] {
                let mesh = MeshResource.generatePlane(width: stripeWidth, depth: segLength)
                let strip = ModelEntity(mesh: mesh, materials: [lineMat])
                strip.position = mid + perpNWSE * stripeOff
                strip.orientation = simd_quatf(angle: .pi / 4, axis: [0, 1, 0])
                fieldContainer.addChild(strip)
            }
        }
    }
}
