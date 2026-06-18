import RealityKit
import simd

// Pin placement is driven from a single array of specs. Add entries to
// `PinLayout.pins` and the runtime will clone the matching colored prefab
// (RedBluePin / YellowYellowPin / RedYellowPin / BlueYellowPin from RCP)
// at the requested position + orientation. Leave the array empty to keep
// whatever pins you've hand-placed in RCP.
//
// Coordinate frame is world space (after any `FieldOrigin` parent offset).
// X = left/right (east is +X), Y = up, Z = forward/back (south is +Z given
// the field's current orientation). Pin base sits at world Y ≈ 0.023 (top
// of floor) — use `PinSpec.standingY` for a default.

enum PinVariant: String {
    case redBlue      = "RedBluePin"
    case yellowYellow = "YellowYellowPin"
    case redYellow    = "RedYellowPin"
    case blueYellow   = "BlueYellowPin"
}

// Native pin model stands along +Y. Each case below is the rotation that
// reorients the pin in world space.
enum PinOrientation {
    case vertical              // standing upright, +Y
    case verticalFlipped       // upside-down, -Y
    case horizontalNorth       // lying down, long axis points -Z
    case horizontalSouth       // lying down, long axis points +Z
    case horizontalEast        // lying down, long axis points +X
    case horizontalWest        // lying down, long axis points -X

    var quaternion: simd_quatf {
        switch self {
        case .vertical:         return simd_quatf(angle: 0,         axis: [0, 1, 0])
        case .verticalFlipped:  return simd_quatf(angle: .pi,       axis: [1, 0, 0])
        case .horizontalNorth:  return simd_quatf(angle: -.pi / 2,  axis: [1, 0, 0])
        case .horizontalSouth:  return simd_quatf(angle:  .pi / 2,  axis: [1, 0, 0])
        case .horizontalEast:   return simd_quatf(angle: -.pi / 2,  axis: [0, 0, 1])
        case .horizontalWest:   return simd_quatf(angle:  .pi / 2,  axis: [0, 0, 1])
        }
    }
}

struct PinSpec {
    let variant: PinVariant
    let position: SIMD3<Float>
    let orientation: PinOrientation

    // Convenience init for a standing pin — pass only X / Z and the Y
    // defaults to the floor height. Bump `verticalAxisYOffset` if your
    // imported model's pivot isn't at the base.
    init(_ variant: PinVariant,
         x: Float,
         z: Float,
         orientation: PinOrientation = .vertical) {
        self.variant = variant
        self.position = SIMD3(x, PinSpec.standingY, z)
        self.orientation = orientation
    }

    init(_ variant: PinVariant,
         position: SIMD3<Float>,
         orientation: PinOrientation = .vertical) {
        self.variant = variant
        self.position = position
        self.orientation = orientation
    }

    // Y at which a standing pin's base touches the field floor surface.
    static let standingY: Float = 0.023
}

enum PinLayout {
    // Best-effort reconstruction of the birdseye reference screenshot. Field
    // is centered at world origin; X is east/west (+X = east, right of
    // screenshot), Z is north/south (+Z = south, bottom of screenshot).
    // Coordinates are eyeballed — tune by hand once you can compare them
    // against the running sim.
    static let pins: [PinSpec] = [
        // --- Center diamond: four upright pins flanking the small square
        // at field center.
        PinSpec(.yellowYellow, x:  0.00, z: -0.32),
        PinSpec(.yellowYellow, x:  0.32, z:  0.00),
        PinSpec(.yellowYellow, x:  0.00, z:  0.32),
        PinSpec(.yellowYellow, x: -0.32, z:  0.00),

        // --- NW star (red-side): vertical core + four horizontal radiators.
        PinSpec(.redBlue,   x: -0.85, z: -0.70),
        PinSpec(.redYellow, x: -1.15, z: -0.70, orientation: .horizontalWest),
        PinSpec(.redYellow, x: -0.55, z: -0.70, orientation: .horizontalEast),
        PinSpec(.redYellow, x: -0.85, z: -0.40, orientation: .horizontalSouth),
        PinSpec(.redYellow, x: -0.85, z: -1.00, orientation: .horizontalNorth),

        // --- NE star (blue-side).
        PinSpec(.blueYellow, x:  0.85, z: -0.55),
        PinSpec(.blueYellow, x:  1.15, z: -0.55, orientation: .horizontalEast),
        PinSpec(.blueYellow, x:  0.55, z: -0.55, orientation: .horizontalWest),
        PinSpec(.blueYellow, x:  0.85, z: -0.25, orientation: .horizontalSouth),
        PinSpec(.blueYellow, x:  0.85, z: -0.85, orientation: .horizontalNorth),

        // --- SW star (red-side).
        PinSpec(.redBlue,   x: -0.55, z:  0.85),
        PinSpec(.redYellow, x: -0.85, z:  0.85, orientation: .horizontalWest),
        PinSpec(.redYellow, x: -0.25, z:  0.85, orientation: .horizontalEast),
        PinSpec(.redYellow, x: -0.55, z:  0.55, orientation: .horizontalNorth),
        PinSpec(.redYellow, x: -0.55, z:  1.15, orientation: .horizontalSouth),

        // --- SE star (blue-side).
        PinSpec(.blueYellow, x:  0.90, z:  0.85),
        PinSpec(.blueYellow, x:  1.20, z:  0.85, orientation: .horizontalEast),
        PinSpec(.blueYellow, x:  0.60, z:  0.85, orientation: .horizontalWest),
        PinSpec(.blueYellow, x:  0.90, z:  0.55, orientation: .horizontalNorth),
        PinSpec(.blueYellow, x:  0.90, z:  1.15, orientation: .horizontalSouth),

        // --- Yellow scatter along midline / cardinal axes.
        PinSpec(.yellowYellow, x: -1.55, z:  0.00),
        PinSpec(.yellowYellow, x:  1.55, z:  0.00),
        PinSpec(.yellowYellow, x:  0.00, z: -1.55),
        PinSpec(.yellowYellow, x:  0.00, z:  1.55),

        // --- Alliance-corner vertical singles, color matching corner.
        PinSpec(.redBlue,     x: -1.45, z: -1.45),
        PinSpec(.blueYellow,  x:  1.45, z: -1.45),
        PinSpec(.redBlue,     x: -1.45, z:  1.45),
        PinSpec(.blueYellow,  x:  1.45, z:  1.45),

        // --- Inner halfway pins between star clusters and the center.
        PinSpec(.yellowYellow, x: -0.45, z: -0.45, orientation: .horizontalEast),
        PinSpec(.yellowYellow, x:  0.45, z: -0.45, orientation: .horizontalWest),
        PinSpec(.yellowYellow, x: -0.45, z:  0.45, orientation: .horizontalEast),
        PinSpec(.yellowYellow, x:  0.45, z:  0.45, orientation: .horizontalWest),
    ]
}
