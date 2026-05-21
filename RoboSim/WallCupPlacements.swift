import RealityKit

// 6 cups per perimeter wall (N / S / E / W), split into 2 groups of 3 on
// either side of the wall's midpoint. The middle cup of each group of 3
// also gets a yellow/yellow pin stacked on top — 24 cups + 8 pins total.
//
// Cup + pin are appended to the same static lists used by the diamond
// stacks. Both spawn together at sim start (the pin spawn height sits
// just above the cup's spawn height) so the pin falls into the cup as it
// settles, identical to the in-field diamond / double-line stacks.
enum WallCupPlacements {

    static func add(pins: inout [Placements.PinPlacement],
                    cups: inout [Placements.CupPlacement]) {
        let halfField = SimulationConstants.halfField
        let cupOnWallY:       Float =  0.1    // matches InFieldPlacements.inFieldCupY
        let pinAboveWallCupY: Float =  0.21   // matches InFieldPlacements.inFieldPinAboveCup
        let wallCupOffsets: [Float] = [-0.7, -0.6, -0.5, 0.5, 0.6, 0.7]   // 2 groups of 3
        // Each wall's cups are shifted inward (toward the field center) so
        // they don't sit on the wall's outer edge.
        let wallCupInwardShift: Float = 0.08
        let wallPinOffsets: Set<Float> = [-0.6, 0.6]

        // N (+Z) and S (-Z) walls — cups vary along X.
        for (wallZ, inwardSignZ) in [(halfField, Float(-1)), (-halfField, Float(1))] {
            let cupZ = wallZ + wallCupInwardShift * inwardSignZ
            for off in wallCupOffsets {
                cups.append((SIMD3<Float>(off, cupOnWallY, cupZ), false))   // opaque side up
                if wallPinOffsets.contains(off) {
                    pins.append((SIMD3<Float>(off, pinAboveWallCupY, cupZ),
                                 .yellow, .yellow, .vertical, nil))
                }
            }
        }
        // E (+X) and W (-X) walls — cups vary along Z.
        for (wallX, inwardSignX) in [(halfField, Float(-1)), (-halfField, Float(1))] {
            let cupX = wallX + wallCupInwardShift * inwardSignX
            for off in wallCupOffsets {
                cups.append((SIMD3<Float>(cupX, cupOnWallY, off), false))   // opaque side up
                if wallPinOffsets.contains(off) {
                    pins.append((SIMD3<Float>(cupX, pinAboveWallCupY, off),
                                 .yellow, .yellow, .vertical, nil))
                }
            }
        }
    }
}
