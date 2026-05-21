import RealityKit

// In-field pregame pieces. Matches the reference top-down image: pins are
// mostly lying flat and scattered, with a handful of vertical pins — each
// of which sits on top of a cup.
enum InFieldPlacements {

    static func add(pins: inout [Placements.PinPlacement],
                    cups: inout [Placements.CupPlacement]) {
        let insideSpawnY:       Float = 0.05   // drop height for horizontal pins
        let inFieldCupY:        Float = 0.1    // drop height for in-field cups
        let inFieldPinAboveCup: Float = 0.21   // pin drops from this Y onto its cup

        // --- Horizontal pins, scattered (no grid) -----------------------
        // (x, z) units = metres, (-1.825, +1.825).
        //
        // === HORIZONTAL PIN YAW =========================================
        // `yawDegrees` rotates the pin around world Y so the long axis
        // points the way you want. Use 0 / 90 / 180 / 270 to snap to a
        // compass direction (any other angle also works):
        //
        //   yawDegrees =   0  → long axis along +X
        //   yawDegrees =  90  → long axis along +Z
        //   yawDegrees = 180  → long axis along -X
        //   yawDegrees = 270  → long axis along -Z
        //
        // 360 is equivalent to 0; flips (180) and identity (0) look the
        // same on a symmetric pin. Change a row's `yawDegrees` to spin
        // just that pin.
        // ================================================================
        struct ScatteredHorizontalPinSpec {
            let position:    SIMD3<Float>
            let top:         PinHalfColor
            let bottom:      PinHalfColor
            let yawDegrees:  Float          // 0 / 90 / 180 / 270 (or any angle)
        }
        let scatteredHorizontalPins: [ScatteredHorizontalPinSpec] = [
            // Around each far cup - Northwest
            ScatteredHorizontalPinSpec(position: SIMD3<Float>(-1.05, insideSpawnY, -1.2),  top: .blue, bottom: .yellow, yawDegrees: 270),
            ScatteredHorizontalPinSpec(position: SIMD3<Float>(-1.2,  insideSpawnY, -1.05), top: .red,  bottom: .yellow, yawDegrees: 180),
            ScatteredHorizontalPinSpec(position: SIMD3<Float>(-1.2,  insideSpawnY, -1.35), top: .blue, bottom: .yellow, yawDegrees: 0),
            ScatteredHorizontalPinSpec(position: SIMD3<Float>(-1.35, insideSpawnY, -1.2),  top: .red,  bottom: .yellow, yawDegrees: 90),

            // Around each near cup - Northwest
            ScatteredHorizontalPinSpec(position: SIMD3<Float>(-0.45, insideSpawnY, -0.6),  top: .blue, bottom: .yellow, yawDegrees:  270),
            ScatteredHorizontalPinSpec(position: SIMD3<Float>(-0.6,  insideSpawnY, -0.45), top: .red,  bottom: .yellow, yawDegrees:  180),
            ScatteredHorizontalPinSpec(position: SIMD3<Float>(-0.6,  insideSpawnY, -0.75), top: .blue, bottom: .yellow, yawDegrees:    0),
            ScatteredHorizontalPinSpec(position: SIMD3<Float>(-0.75, insideSpawnY, -0.6),  top: .red,  bottom: .yellow, yawDegrees:   90),

            // Around each far cup - Southeast
            ScatteredHorizontalPinSpec(position: SIMD3<Float>(1.05,  insideSpawnY, 1.2),   top: .red,  bottom: .yellow, yawDegrees:   90),
            ScatteredHorizontalPinSpec(position: SIMD3<Float>(1.2,   insideSpawnY, 1.05),  top: .blue, bottom: .yellow, yawDegrees:    0),
            ScatteredHorizontalPinSpec(position: SIMD3<Float>(1.2,   insideSpawnY, 1.35),  top: .red,  bottom: .yellow, yawDegrees:  180),
            ScatteredHorizontalPinSpec(position: SIMD3<Float>(1.35,  insideSpawnY, 1.2),   top: .blue, bottom: .yellow, yawDegrees:  270),

            // Around each near cup - Southeast
            ScatteredHorizontalPinSpec(position: SIMD3<Float>(0.45,  insideSpawnY, 0.6),   top: .red,  bottom: .yellow, yawDegrees:   90),
            ScatteredHorizontalPinSpec(position: SIMD3<Float>(0.6,   insideSpawnY, 0.45),  top: .blue, bottom: .yellow, yawDegrees:    0),
            ScatteredHorizontalPinSpec(position: SIMD3<Float>(0.6,   insideSpawnY, 0.75),  top: .red,  bottom: .yellow, yawDegrees:  180),
            ScatteredHorizontalPinSpec(position: SIMD3<Float>(0.75,  insideSpawnY, 0.6),   top: .blue, bottom: .yellow, yawDegrees:  270),
        ]
        for spec in scatteredHorizontalPins {
            pins.append((spec.position, spec.top, spec.bottom, .horizontal, spec.yawDegrees))
        }

        // --- Vertical pins (each one is paired with a cup beneath) ------
        // 4 stacks at the diamond's N/E/S/W corners, plus 2 stacks along
        // each of the 4 diagonals stemming from the diamond's edge
        // midpoints out to the field corners (8 total).
        let inFieldStackXZ: [(Float, Float)] = [
            // Diamond corners (4)
            ( 0.00,  0.60),   // N corner of diamond
            ( 0.60,  0.00),   // E
            ( 0.00, -0.60),   // S
            (-0.60,  0.00),   // W
            // NW diagonal
            (-0.60,  0.60),
            (-1.20,  1.20),
            // NE diagonal
            ( 0.60,  0.60),
            ( 1.20,  1.20),
            // SW diagonal
            (-0.60, -0.60),
            (-1.20, -1.20),
            // SE diagonal
            ( 0.60, -0.60),
            ( 1.20, -1.20),
        ]

        // === STACK-PIN PLACEMENTS =======================================
        //   x, z          — where the cup beneath this pin lives
        //   topColor /    — alliance halves of the pin asset. The asset
        //   bottomColor    name is `\(top)\(bottom)Pin`, so only combos
        //                  that exist in Scene.usda are valid.
        //   flipVertical  — false: pin stands with `topColor` facing up.
        //                  true: pin rotated 180° so `bottomColor` faces
        //                  up (useful when only one asset exists but you
        //                  want both orientations). No-op for yellow/yellow.
        struct StackPinSpec {
            let x: Float
            let z: Float
            let topColor: PinHalfColor
            let bottomColor: PinHalfColor
            let flipVertical: Bool
        }
        let inFieldStackPins: [StackPinSpec] = [
            // Diamond corners — N & E stand red-up; S & W are flipped so
            // blue ends up on top.
            StackPinSpec(x:  0.00, z:  0.60, topColor: .red, bottomColor: .blue, flipVertical: false),
            StackPinSpec(x:  0.60, z:  0.00, topColor: .red, bottomColor: .blue, flipVertical: true),
            StackPinSpec(x:  0.00, z: -0.60, topColor: .red, bottomColor: .blue, flipVertical: true),
            StackPinSpec(x: -0.60, z:  0.00, topColor: .red, bottomColor: .blue, flipVertical: false),

            // Yellow/yellow pins on the double-line (NW & SE diagonals).
            // Flip is a visual no-op for these.
            StackPinSpec(x: -0.60, z:  0.60, topColor: .yellow, bottomColor: .yellow, flipVertical: false),
            StackPinSpec(x: -1.20, z:  1.20, topColor: .yellow, bottomColor: .yellow, flipVertical: false),
            StackPinSpec(x:  0.60, z: -0.60, topColor: .yellow, bottomColor: .yellow, flipVertical: false),
            StackPinSpec(x:  1.20, z: -1.20, topColor: .yellow, bottomColor: .yellow, flipVertical: false),
        ]

        for (x, z) in inFieldStackXZ {
            cups.append((SIMD3<Float>(x, inFieldCupY, z), true))
        }
        for spec in inFieldStackPins {
            let stance: PinStance = spec.flipVertical ? .verticalFlipped : .vertical
            pins.append((SIMD3<Float>(spec.x, inFieldPinAboveCup, spec.z),
                         spec.topColor, spec.bottomColor, stance, nil))
        }
    }
}
