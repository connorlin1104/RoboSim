import RealityKit

// Tracks everything we need to respawn a pin if it falls off the field.
struct GamePin {
    let entity: Entity
    let spawn: SIMD3<Float>
    let shape: ShapeResource
}

// Builds physics-ready pin instances out of the master Reality Composer Pro
// scene. Each call clones the appropriate `\(top)\(bottom)Pin` template so
// pins of the same colour don't share a single entity.
enum PinFactory {

    static let physicsMaterial = PhysicsMaterialResource.generate(friction: 0.6, restitution: 0.1)

    // Strip any physics/collision components that came in from the
    // Reality Composer Pro scene. If RCP attached its own bodies, the
    // hierarchy ends up with two competing physics descriptions and
    // things stop colliding or stop stacking correctly. We clear the
    // whole subtree so our procedurally-attached body is the only one.
    @MainActor
    static func stripPhysics(_ entity: Entity) {
        entity.components.remove(PhysicsBodyComponent.self)
        entity.components.remove(CollisionComponent.self)
        entity.components.remove(PhysicsMotionComponent.self)
        for child in entity.children {
            stripPhysics(child)
        }
    }

    @MainActor
    static func makePin(top: PinHalfColor,
                        bottom: PinHalfColor,
                        at position: SIMD3<Float>,
                        stance: PinStance,
                        yawDegrees: Float? = nil,
                        isStatic: Bool = false,
                        scene: Entity) -> GamePin? {
        let assetName = "\(top.rawValue)\(bottom.rawValue)Pin"
        guard let template = scene.findEntity(named: assetName) else {
            print("[RoboSim] Missing pin asset: \(assetName) (add it to Scene.usda in Reality Composer Pro)")
            return nil
        }
        let pin = template.clone(recursive: true)
        stripPhysics(pin)

        // === PIN ORIENTATION ============================================
        // `stanceRotation` puts the pin into the requested pose; then a
        // yaw rotation is applied around world Y. By default that yaw is
        // a deterministic per-position jitter (so a grid of pins doesn't
        // look identical). Pass `yawDegrees` to override — pick from
        // 0 / 90 / 180 / 270, or any other angle.
        //
        // `.verticalFlipped` adds an extra 180° roll on top of the
        // standard vertical pose so the half that would normally face up
        // ends up facing down (useful when only one colour-combo asset
        // exists but you need both orientations on the field).
        //
        // If pins come out lying down when you ask for `.vertical` (or
        // vice-versa), the source .usdz was authored with a different
        // "up" axis — swap in one of the alternatives below:
        //
        //   `.vertical`   options (one of these makes the pin stand up):
        //     simd_quatf()                                       // long axis already = Y
        //     simd_quatf(angle:  .pi / 2, axis: [1, 0, 0])       // long axis = -Z in source
        //     simd_quatf(angle: -.pi / 2, axis: [1, 0, 0])       // long axis = +Z in source
        //     simd_quatf(angle:  .pi / 2, axis: [0, 0, 1])       // long axis = X in source
        //
        //   `.horizontal` options (pin lying on its side):
        //     simd_quatf()                                       // if source pin already lies flat
        //     simd_quatf(angle: .pi / 2, axis: [0, 0, 1])        // tip Y-up source onto its side
        //
        let stanceRotation: simd_quatf
        switch stance {
        case .vertical:
            stanceRotation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
        case .verticalFlipped:
            // Stand the pin up, then roll 180° around Z so its top half
            // ends up facing down.
            stanceRotation = simd_quatf(angle: .pi, axis: [0, 0, 1])
                * simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
        case .horizontal:
            // Explicit identity quaternion. `simd_quatf()` zero-initializes
            // to (0,0,0,0), which is NOT identity — composing with it
            // wipes any subsequent yaw, which is why yawDegrees did
            // nothing for horizontal pins until this was fixed.
            stanceRotation = simd_quatf(real: 1, imag: SIMD3<Float>(0, 0, 0))
        }
        let yawRadians: Float
        if let yawDegrees = yawDegrees {
            yawRadians = yawDegrees * .pi / 180
        } else {
            // Fallback: deterministic per-position jitter.
            yawRadians = (position.x * 7.13 + position.z * 3.17).truncatingRemainder(dividingBy: 2 * .pi)
        }
        let yawRotation = simd_quatf(angle: yawRadians, axis: [0, 1, 0])
        pin.orientation = yawRotation * stanceRotation
        // =================================================================

        pin.scale *= 0.5
        pin.position = position

        // Bounds are computed in the pin's local space (independent of
        // pin's own orientation/scale). The collision shape we generate
        // here therefore needs to match the model's *unrotated* extents;
        // it then inherits the pin's transform along with the visual mesh
        // and stays aligned with it in world space.
        //
        // `pinBaseFraction = 1.0` means the collider exactly matches the
        // visual bounding box. Lower values produce a narrower base
        // (more tippable) but also leave the pin's visible mesh poking
        // out of the collider — when the pin lies on its side, that
        // overshoot ends up below the floor, which is the "phasing"
        // you were seeing. Keeping it at 1.0 trades a little tippability
        // for clean ground contact in every orientation.
        let bounds = pin.visualBounds(relativeTo: pin)
        let h = bounds.extents
        let pinBaseFraction: Float = 1.0
        let collisionExtents = SIMD3<Float>(
            h.x * pinBaseFraction,
            h.y * pinBaseFraction,
            h.z * pinBaseFraction
        )

        let shape = ShapeResource.generateBox(size: collisionExtents)
            .offsetBy(translation: bounds.center)
        // `isStatic` pins (the pregame layout) don't fall under gravity
        // and don't shift when something nudges them. Match-load drops
        // pass false so those land dynamically.
        let bodyMode: PhysicsBodyMode = isStatic ? .static : .dynamic
        let bodyMass: Float           = isStatic ? 0      : 0.1
        var body = PhysicsBodyComponent(shapes: [shape], mass: bodyMass, material: physicsMaterial, mode: bodyMode)
        body.linearDamping = 0.2
        // Low angular damping → once a pin starts tipping, the rotation
        // isn't bled off and gravity finishes the fall.
        body.angularDamping = 0.15
        pin.components.set(CollisionComponent(shapes: [shape]))
        pin.components.set(body)
        pin.components.set(PhysicsMotionComponent())

        return GamePin(entity: pin, spawn: position, shape: shape)
    }
}
