import RealityKit

// Cups are containers that hold pins. They are *always* vertical; the only
// choice is right-side-up (default) vs. upside-down. The collider is a
// hollow tube with a mid-height shelf so pins falling in stop at the cup's
// center rather than dropping all the way through.
enum CupFactory {

    @MainActor
    static func makeCup(at position: SIMD3<Float>,
                        upsideDown: Bool,
                        isStatic: Bool = false,
                        surfaceMaterial: PhysicsMaterialResource,
                        scene: Entity) -> Entity? {
        let assetName = "cupModel"
        guard let template = scene.findEntity(named: assetName) else {
            print("[RoboSim] Missing cup asset: \(assetName) (add it to Scene.usda in Reality Composer Pro)")
            return nil
        }
        let cup = template.clone(recursive: true)
        PinFactory.stripPhysics(cup)

        // === CUP ORIENTATION ============================================
        // Cups are *always* vertical. `cupUprightRotation` puts the
        // opening up; multiplying by a π-around-Z flip turns the cup
        // upside-down.
        //
        // If cups come out lying on their side or upside-down by default,
        // swap `cupUprightRotation` for one of these until they stand on
        // their bottoms:
        //
        //   simd_quatf()                                      // long axis = Y already
        //   simd_quatf(angle:  .pi / 2, axis: [1, 0, 0])      // long axis = -Z in source
        //   simd_quatf(angle: -.pi / 2, axis: [1, 0, 0])      // long axis = +Z in source
        //   simd_quatf(angle:  .pi / 2, axis: [0, 0, 1])      // long axis = X in source
        //
        // The flip rotation can also be swapped (e.g. around X instead of
        // Z) if upside-down looks wrong.
        let flipRotation = upsideDown
            ? simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
            : simd_quatf(angle: -.pi / 2, axis: [1, 0, 0])
        cup.orientation = flipRotation
        // =================================================================

        cup.scale *= 0.5
        cup.position = position

        // === HOLLOW CUP COLLIDER (open both ends, mid-height shelf) =====
        // The cup is modeled as a tube — open at BOTH ends — with a thin
        // internal shelf at the mid-height of the cup. A pin dropped in
        // from the top falls until it hits the shelf, so only its bottom
        // half sits inside the cup's upper half and the top half of the
        // pin sticks out above the rim.
        //
        // Geometry: 5 thin box shapes attached as a compound collider:
        //   • 4 perimeter walls (full cup length along the long axis)
        //   • 1 mid-height shelf (perpendicular slab at the cup's center
        //     along the long axis)
        //
        // Tunables:
        //   wellWallThickness — wall / shelf thickness; smaller = more
        //     interior room but easier for pins to clip through at speed
        //   shelfPositionFraction — 0.0 puts the shelf at the cup's
        //     -longAxis end, 1.0 at the +longAxis end, 0.5 dead center.
        //     Raise to make the pin protrude more, lower to make it sink
        //     deeper.
        let bounds = cup.visualBounds(relativeTo: cup)
        let h = bounds.extents
        let center = bounds.center
        let longAxis: Int   = (h.x >= h.y && h.x >= h.z) ? 0 : (h.y >= h.z ? 1 : 2)
        let shortAxis1: Int = (longAxis + 1) % 3
        let shortAxis2: Int = (longAxis + 2) % 3

        // `interiorFraction` controls how far inside the visual cup the
        // walls live. 1.0 = walls flush with the visualBounds (the old
        // behaviour, which left a gap between the cup's visible inner
        // surface and the collision wall — pins phased through). 0.7 =
        // walls sit at 70% of the visual half-width, putting them
        // approximately at the cup's actual inner surface. Lower this if
        // pins still phase through; raise it if the pin no longer fits
        // through the opening.
        //
        // wellWallThickness is in *cup-local* coordinates (before the
        // cup's 0.5 scale is applied). Keep it small enough that the
        // wall's outer face stays inside the visualBounds half-width.
        let wellWallThickness:     Float = 0.02
        let interiorFraction:      Float = 0.9     // wider well so pins clear the rim
        let shelfPositionFraction: Float = 0.5     // 0.5 = dead-centre shelf

        let interiorHalf1 = h[shortAxis1] * interiorFraction / 2
        let interiorHalf2 = h[shortAxis2] * interiorFraction / 2

        // Mid-height shelf — slab perpendicular to long axis, sized to
        // the cup's INTERIOR cross-section so the pin lands centered.
        var shelfSize = SIMD3<Float>(repeating: 0)
        shelfSize[longAxis]   = wellWallThickness
        shelfSize[shortAxis1] = interiorHalf1 * 2
        shelfSize[shortAxis2] = interiorHalf2 * 2
        var shelfOffset = center
        shelfOffset[longAxis] += (shelfPositionFraction - 0.5) * h[longAxis]
        let shelfShape = ShapeResource.generateBox(size: shelfSize)
            .offsetBy(translation: shelfOffset)

        // 4 perimeter walls — positioned on the cup's INSIDE surface (at
        // the interior half-width, plus half a wall-thickness so the
        // wall's inner face is exactly at that boundary).
        func makeWall(shortSign: Float, isAxis1: Bool) -> ShapeResource {
            var size = SIMD3<Float>(repeating: 0)
            size[longAxis]   = h[longAxis]
            size[shortAxis1] = isAxis1 ? wellWallThickness : interiorHalf1 * 2
            size[shortAxis2] = isAxis1 ? interiorHalf2 * 2 : wellWallThickness
            var off = center
            let axis      = isAxis1 ? shortAxis1   : shortAxis2
            let halfWidth = isAxis1 ? interiorHalf1 : interiorHalf2
            off[axis] += shortSign * (halfWidth + wellWallThickness / 2)
            return ShapeResource.generateBox(size: size).offsetBy(translation: off)
        }
        let cupShapes: [ShapeResource] = [
            shelfShape,
            makeWall(shortSign: -1, isAxis1: true),
            makeWall(shortSign:  1, isAxis1: true),
            makeWall(shortSign: -1, isAxis1: false),
            makeWall(shortSign:  1, isAxis1: false),
        ]

        // `isStatic` cups (the pregame layout) don't drop and don't
        // wobble on contact — they just sit where placed. Pass false for
        // match-loaded cups so they fall under gravity.
        let bodyMode: PhysicsBodyMode = isStatic ? .static : .dynamic
        let bodyMass: Float           = isStatic ? 0      : 0.25
        var cupBody = PhysicsBodyComponent(shapes: cupShapes, mass: bodyMass, material: surfaceMaterial, mode: bodyMode)
        cupBody.linearDamping  = 0.3
        cupBody.angularDamping = 0.9   // very hard to tip — keeps cups roughly vertical
        cup.components.set(CollisionComponent(shapes: cupShapes))
        cup.components.set(cupBody)
        cup.components.set(PhysicsMotionComponent())
        // =================================================================

        return cup
    }
}
