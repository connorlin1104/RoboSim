import RealityKit

// Computes the static pregame layout for every pin and cup on the field.
// Returns the lists used downstream:
//   • pinPlacements – every pin spawned at sim start (position + colors +
//     stance)
//   • cupPlacements – every cup spawned at sim start (position +
//     upsideDown flag)
//   • deferredWallStackPins – yellow/yellow pins to drop ~1s later on top
//     of the wall cups, once those cups have settled
enum Placements {

    typealias PinPlacement = (position: SIMD3<Float>,
                              top: PinHalfColor,
                              bottom: PinHalfColor,
                              stance: PinStance)
    typealias CupPlacement = (position: SIMD3<Float>, upsideDown: Bool)

    struct Result {
        let pins: [PinPlacement]
        let cups: [CupPlacement]
        let deferredWallStackPins: [SIMD3<Float>]
    }

    static func compute(platform: LoadingZones.PlatformGeometry) -> Result {
        var pins:  [PinPlacement] = []
        var cups:  [CupPlacement] = []
        var deferredWallStackPins: [SIMD3<Float>] = []

        InFieldPlacements.add(pins: &pins, cups: &cups)
        LoaderRowPlacements.add(pins: &pins, cups: &cups, platform: platform)
        WallCupPlacements.add(cups: &cups, deferred: &deferredWallStackPins)

        return Result(pins: pins, cups: cups, deferredWallStackPins: deferredWallStackPins)
    }
}
