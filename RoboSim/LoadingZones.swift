import RealityKit
import UIKit

// Built outside the field perimeter on the west (red) and east (blue) sides:
//   • match-load chutes (one per corner — NW/SW red, NE/SE blue) using the
//     RedMatchloader / BlueMatchloader assets out of the master scene
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

    private enum ChuteAlliance { case red, blue }

    @MainActor
    static func build(into fieldContainer: Entity,
                      surfaceMaterial: PhysicsMaterialResource,
                      masterScene: Entity?) -> PlatformGeometry {
        addChutesAndLTape(into: fieldContainer, masterScene: masterScene)
        return addLoaderPlatforms(into: fieldContainer, surfaceMaterial: surfaceMaterial)
    }

    // --- MATCH LOAD CHUTES (Matchloader assets + L-shape tape on floor) ---
    @MainActor
    private static func addChutesAndLTape(into fieldContainer: Entity,
                                          masterScene: Entity?) {
        let halfField = SimulationConstants.halfField
        let tileSize  = SimulationConstants.tileSize
        let tapeIntoField: Float = tileSize / 2
        let tapeWidth: Float = 0.035

        // 4 chutes: 2 red (W wall, NW + SW), 2 blue (E wall, NE + SE)
        // -----------------------------------------------------------------
        // CHUTE PLACEMENT — change the per-corner positions below.
        // Each chute's world position is set by `ChuteSpec.pos`. To move a
        // single chute (e.g. just the NE blue one), edit that corner's
        // SIMD3 below. `chuteWallInset` / `chuteCornerInset` move all four
        // chutes uniformly toward / away from the perimeter.
        // -----------------------------------------------------------------
        let chuteWallInset: Float = tapeIntoField / 2 - 0.1    // distance from perimeter wall into field
        let chuteCornerInset: Float = 0.5 * tileSize           // distance from field corner along the wall

        struct ChuteSpec { let pos: SIMD3<Float>; let yRot: Float; let alliance: ChuteAlliance }

        let nwPos = SIMD3<Float>(-halfField + chuteWallInset, 0.15,  halfField - chuteCornerInset)   // NW chute world position
        let swPos = SIMD3<Float>(-halfField + chuteWallInset, 0.15, -halfField + chuteCornerInset)   // SW chute world position
        let nePos = SIMD3<Float>( halfField - chuteWallInset, 0.15,  halfField - chuteCornerInset)   // NE chute world position
        let sePos = SIMD3<Float>( halfField - chuteWallInset, 0.15, -halfField + chuteCornerInset)   // SE chute world position

        let chuteSpecs: [ChuteSpec] = [
            ChuteSpec(pos: nwPos, yRot: 0,    alliance: .red),   // NW
            ChuteSpec(pos: swPos, yRot: 0,    alliance: .red),   // SW
            ChuteSpec(pos: nePos, yRot: .pi,  alliance: .blue),  // NE — edit `nePos` above to move this one
            ChuteSpec(pos: sePos, yRot: .pi,  alliance: .blue),  // SE
        ]

        for spec in chuteSpecs {
            let chute = makeMatchloader(alliance: spec.alliance, masterScene: masterScene)
            chute.position = spec.pos
            // Authoring rotation around Y so the matchloader's opening faces
            // into the field. The yRot from the spec flips W-wall chutes to
            // E-wall chutes; if the asset comes in facing the wrong way,
            // tweak `matchloaderModelYawOffset` in `makeMatchloader` below.
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

    // Clone a Matchloader asset from the master Reality Composer Pro scene.
    // Red alliance → `RedMatchloader`, Blue alliance → `BlueMatchloader`.
    // Each asset comes with its own scale baked into Scene.usda; we just
    // wrap it in a holder Entity at the origin and let the spec set the
    // world transform.
    //
    // If the asset comes in too big/small or facing the wrong way,
    // adjust `matchloaderScale` or `matchloaderModelYawOffset` here —
    // those are the two knobs that affect every chute uniformly.
    @MainActor
    private static func makeMatchloader(alliance: ChuteAlliance,
                                        masterScene: Entity?) -> Entity {
        let matchloaderScale: Float = 0.40           // multiplier on top of the .usdz's own scale
        let matchloaderModelYawOffset: Float = -.pi / 2    // tweak (in radians) if the asset's opening faces wrong way

        let holder = Entity()
        let assetName: String = (alliance == .red) ? "RedMatchloader" : "BlueMatchloader"
        guard let masterScene, let template = masterScene.findEntity(named: assetName) else {
            print("[RoboSim] Missing matchloader asset: \(assetName) (add it to Scene.usda in Reality Composer Pro)")
            return holder
        }
        let model = template.clone(recursive: true)
        // Drop the .usdz translation baked into Scene.usda — we want the
        // matchloader sitting at the holder's origin so the spec's
        // chute-position controls placement.
        model.position = .zero
        model.scale *= matchloaderScale
        model.orientation = simd_quatf(angle: matchloaderModelYawOffset, axis: [0, 1, 0]) * model.orientation
        holder.addChild(model)
        return holder
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
