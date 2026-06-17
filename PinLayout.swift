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
    // Add specs here. Leave empty to use the pins you hand-placed in RCP.
    //
    // Example:
    // PinSpec(.redBlue,      x:  0.50, z: -1.20),
    // PinSpec(.yellowYellow, x: -0.50, z: -1.20, orientation: .horizontalEast),
    static let pins: [PinSpec] = [
        PinSpec(.redBlue,      x:  0.50, z: -1.20),
        PinSpec(.yellowYellow, x: -0.50, z: -1.20, orientation: .horizontalEast),
        PinSpec(.redYellow,    x:  0.00, z:  0.00, orientation: .verticalFlipped),
        PinSpec(.blueYellow,   position: [0.3, 0.5, 0.2], orientation: .horizontalNorth),
    ]
}
