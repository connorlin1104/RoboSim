import RealityKit
import UIKit

// Built outside the field perimeter on the west (red) and east (blue) sides:
//   • match-load chutes (one per corner — NW/SW red, NE/SE blue)
//   • L-shaped floor tape inside each chute corner
//   • big alliance-colored loader platforms slid up against W/E walls
//
// Returns the platform geometry the placement code needs to put pin/cup
// rows on top of the loader platforms.
enum LoadingZones {

    struct PlatformGeometry {
        let topY:          Float
        let westCenterX:   Float
        let eastCenterX:   Float
    }

    @MainActor
    static func build(into fieldContainer: Entity,
                      surfaceMaterial: PhysicsMaterialResource) -> PlatformGeometry {
        addChutesAndLTape(into: fieldContainer)
        return addLoaderPlatforms(into: fieldContainer, surfaceMaterial: surfaceMaterial)
    }

    // --- MATCH LOAD CHUTES (hollow 3D structure + U-shape tape on floor) -
    @MainActor
    private static func addChutesAndLTape(into fieldContainer: Entity) {
        let halfField = SimulationConstants.halfField
        let tileSize  = SimulationConstants.tileSize
        let tapeIntoField: Float = tileSize / 2
        let tapeWidth: Float = 0.035

        // 4 chutes: 2 red (W wall, NW + SW), 2 blue (E wall, NE + SE)
        let chuteWallInset: Float = tapeIntoField / 2 - 0.02
        let chuteCornerInset: Float = 0.5 * tileSize    // chute sits at the end of the L tape's long leg

        struct ChuteSpec { let pos: SIMD3<Float>; let yRot: Float; let color: UIColor }

        let nwPos = SIMD3<Float>(-halfField + chuteWallInset, 0,  halfField - chuteCornerInset)
        let swPos = SIMD3<Float>(-halfField + chuteWallInset, 0, -halfField + chuteCornerInset)
        let nePos = SIMD3<Float>( halfField - chuteWallInset, 0,  halfField - chuteCornerInset)
        let sePos = SIMD3<Float>( halfField - chuteWallInset, 0, -halfField + chuteCornerInset)

        let chuteSpecs: [ChuteSpec] = [
            ChuteSpec(pos: nwPos, yRot: 0,     color: .systemRed),  // NW
            ChuteSpec(pos: swPos, yRot: 0,     color: .systemRed),  // SW
            ChuteSpec(pos: nePos, yRot: .pi,   color: .systemBlue), // NE
            ChuteSpec(pos: sePos, yRot: .pi,   color: .systemBlue)  // SE
        ]

        for spec in chuteSpecs {
            let chute = makeChute(tapeColor: spec.color,
                                  tapeIntoField: tapeIntoField,
                                  tapeWidth: tapeWidth)
            chute.position = spec.pos
            chute.orientation = simd_quatf(angle: spec.yRot, axis: [0, 1, 0])
            fieldContainer.addChild(chute)
        }

        // L-shape floor tape at each match-load corner.
        // - horizontal leg (parallel to N/S wall) is 1/2 tile, runs from the
        //   corner toward the L vertex
        // - vertical leg (parallel to W/E wall) is 1 tile, runs from the L
        //   vertex deeper into the field
        let lTapeSpecs: [(SIMD3<Float>, Float, Float, UIColor)] = [
            // (field corner, xInsideSign, zInsideSign, color)
            ([-halfField, 0,  halfField],  1, -1, .systemRed),    // NW
            ([-halfField, 0, -halfField],  1,  1, .systemRed),    // SW
            ([ halfField, 0,  halfField], -1, -1, .systemBlue),   // NE
            ([ halfField, 0, -halfField], -1,  1, .systemBlue),   // SE
        ]
        for (corner, xInside, zInside, color) in lTapeSpecs {
            let mat = SimpleMaterial(color: color, isMetallic: false)
            let lVertexX = corner.x + xInside * 0.5 * tileSize

            // Horizontal leg (along X, length = 0.5 tile)
            let horiz = ModelEntity(
                mesh: .generatePlane(width: 0.5 * tileSize, depth: tapeWidth),
                materials: [mat]
            )
            horiz.position = [corner.x + xInside * 0.25 * tileSize, 0.003, corner.z * tileSize * 1.1]
            fieldContainer.addChild(horiz)

            // Vertical leg (along Z, length = 1 tile)
            let vert = ModelEntity(
                mesh: .generatePlane(width: tapeWidth, depth: tileSize * 1.045),
                materials: [mat]
            )
            vert.position = [lVertexX, 0.003, corner.z + zInside * 0.5 * tileSize]
            fieldContainer.addChild(vert)
        }
    }

    // Build a chute as if it sits on the W wall (opening toward +X / field).
    // For the E wall, rotate the whole assembly 180° around Y.
    @MainActor
    private static func makeChute(tapeColor: UIColor,
                                  tapeIntoField: Float,
                                  tapeWidth: Float) -> Entity {
        // Chute body — much smaller, fits inside the U
        let chuteW: Float = 0.09   // along the wall direction
        let chuteD: Float = 0.09   // perpendicular into field
        let chuteH: Float = 0.40
        let chuteT: Float = 0.005   // wall thickness
        let chuteBodyMat = SimpleMaterial(color: .lightGray, isMetallic: false)

        let chute = Entity()
        let topMat = SimpleMaterial(color: tapeColor, isMetallic: false)
        // Chute body is shifted toward the back (near the perimeter wall side)
        let bodyOffsetX: Float = -tapeIntoField / 2 + tapeWidth + 0.012 + chuteD / 2

        // Handle that lies on top of the perimeter wall (a person grabs this to lift the loader)
        let handle = ModelEntity(
            mesh: .generateBox(size: [chuteT, chuteT, chuteW - 0.02]),
            materials: [chuteBodyMat]
        )
        handle.position = [bodyOffsetX - chuteD / 2 + chuteT, chuteH + chuteT, 0]
        chute.addChild(handle)

        // Half wall on the field-facing side
        let front = ModelEntity(
            mesh: .generateBox(size: [chuteT, chuteH * 0.7, chuteW]),
            materials: [chuteBodyMat]
        )
        front.position = [bodyOffsetX + chuteD / 2 - chuteT / 2, chuteH * 0.65, 0]
        chute.addChild(front)

        // Two side walls
        for sideZ in [-(chuteW / 2 - chuteT / 2), (chuteW / 2 - chuteT / 2)] {
            let side = ModelEntity(
                mesh: .generateBox(size: [chuteD, chuteH, chuteT]),
                materials: [chuteBodyMat]
            )
            side.position = [bodyOffsetX, chuteH / 2, sideZ]
            chute.addChild(side)
        }

        // Colored U-shaped top: 2 parallel strips along X + 1 connecting strip on the field-interior side
        let topStripT: Float = 0.01
        let topY: Float = chuteH + topStripT / 2
        for stripZ: Float in [-(chuteW / 2 - topStripT / 2), (chuteW / 2 - topStripT / 2)] {
            let strip = ModelEntity(
                mesh: .generateBox(size: [chuteD, topStripT, topStripT]),
                materials: [topMat]
            )
            strip.position = [bodyOffsetX, topY, stripZ]
            chute.addChild(strip)
        }
        let connect = ModelEntity(
            mesh: .generateBox(size: [topStripT, topStripT, chuteW]),
            materials: [topMat]
        )
        connect.position = [bodyOffsetX + chuteD / 2 - topStripT / 2, topY, 0]
        chute.addChild(connect)

        return chute
    }

    // --- LOADER PLATFORMS (alliance-colored slabs just outside W/E walls) -
    @MainActor
    private static func addLoaderPlatforms(into fieldContainer: Entity,
                                           surfaceMaterial: PhysicsMaterialResource) -> PlatformGeometry {
        let fieldSize     = SimulationConstants.fieldSize
        let halfField     = SimulationConstants.halfField
        let wallThickness = SimulationConstants.wallThickness

        let loaderPlatformDepth: Float = 1.5            // X (away from field)
        let loaderPlatformLength: Float = fieldSize     // Z (matches field side)
        let loaderPlatformThickness: Float = 0.1
        let loaderTopY: Float = loaderPlatformThickness        // top surface
        let westPlatformX: Float = -halfField - wallThickness / 2 - loaderPlatformDepth / 2
        let eastPlatformX: Float = -westPlatformX

        let loaderPlatformSize: SIMD3<Float> = [loaderPlatformDepth, loaderPlatformThickness, loaderPlatformLength]
        let loaderPlatformMesh = MeshResource.generateBox(size: loaderPlatformSize)
        let loaderPlatformShape = ShapeResource.generateBox(size: loaderPlatformSize)

        func addPlatform(centerX: Float, color: UIColor) {
            let mat = SimpleMaterial(color: color, isMetallic: false)
            let platform = ModelEntity(mesh: loaderPlatformMesh, materials: [mat])
            platform.position = [centerX, loaderPlatformThickness / 2, 0]
            platform.components.set(PhysicsBodyComponent(shapes: [loaderPlatformShape], mass: 0, material: surfaceMaterial, mode: .static))
            platform.components.set(CollisionComponent(shapes: [loaderPlatformShape]))
            fieldContainer.addChild(platform)
        }
        addPlatform(centerX: westPlatformX, color: .systemRed)   // West = red alliance
        addPlatform(centerX: eastPlatformX, color: .systemBlue)  // East = blue alliance

        return PlatformGeometry(topY: loaderTopY,
                                westCenterX: westPlatformX,
                                eastCenterX: eastPlatformX)
    }
}
