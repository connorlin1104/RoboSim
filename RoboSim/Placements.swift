import RealityKit

// Computes the static pregame layout for every pin and cup on the field.
// Returns the lists used downstream:
//   • pinPlacements – every pin spawned at sim start (position + colors +
//     stance + optional yawDegrees override)
//   • cupPlacements – every cup spawned at sim start (position +
//     upsideDown flag)
enum Placements {

    // `yawDegrees` rotates the pin around world Y. Useful for horizontal
    // pins where 0 / 90 / 180 / 270 picks which compass direction the pin
    // points. Pass nil to fall back to the deterministic per-position
    // jitter in PinFactory.
    typealias PinPlacement = (position: SIMD3<Float>,
                              top: PinHalfColor,
                              bottom: PinHalfColor,
                              stance: PinStance,
                              yawDegrees: Float?)
    typealias CupPlacement = (position: SIMD3<Float>, upsideDown: Bool)

    struct Result {
        let pins: [PinPlacement]
        let cups: [CupPlacement]
    }

    static func compute(platform: LoadingZones.PlatformGeometry) -> Result {
        var pins:  [PinPlacement] = []
        var cups:  [CupPlacement] = []

        InFieldPlacements.add(pins: &pins, cups: &cups)
        LoaderRowPlacements.add(pins: &pins, cups: &cups, platform: platform)
        WallCupPlacements.add(pins: &pins, cups: &cups)

        return Result(pins: pins, cups: cups)
    }
}
