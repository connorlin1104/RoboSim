import RealityKit

// 6 cups per perimeter wall (N / S / E / W), split into 2 groups of 3 on
// either side of the wall's midpoint. The middle cup of each group of 3
// also gets a yellow/yellow pin stacked on top — 24 cups + 8 pins total.
// Pins are deferred so the cups can settle first.
enum WallCupPlacements {

    static func add(cups: inout [Placements.CupPlacement],
                    deferred: inout [SIMD3<Float>]) {
        let halfField = SimulationConstants.halfField
        let cupOnWallY:       Float =  0.1    // cup drops from here
        let pinAboveWallCupY: Float =  0.21   // pin drops from here onto the cup
        let wallCupOffsets: [Float] = [-0.7, -0.6, -0.5, 0.5, 0.6, 0.7]   // 2 groups of 3
        // Each wall's cups are shifted inward (toward the field center) so
        // they don't sit on the wall's outer edge.
        let wallCupInwardShift: Float = 0.077
        let wallPinOffsets: Set<Float> = [-0.6, 0.6]

        // N (+Z) and S (-Z) walls — cups vary along X.
        for (wallZ, inwardSignZ) in [(halfField, Float(-1)), (-halfField, Float(1))] {
            let cupZ = wallZ + wallCupInwardShift * inwardSignZ
            for off in wallCupOffsets {
                cups.append((SIMD3<Float>(off, cupOnWallY, cupZ), true))
                if wallPinOffsets.contains(off) {
                    deferred.append(SIMD3<Float>(off, pinAboveWallCupY, cupZ))
                }
            }
        }
        // E (+X) and W (-X) walls — cups vary along Z.
        for (wallX, inwardSignX) in [(halfField, Float(-1)), (-halfField, Float(1))] {
            let cupX = wallX + wallCupInwardShift * inwardSignX
            for off in wallCupOffsets {
                cups.append((SIMD3<Float>(cupX, cupOnWallY, off), true))
                if wallPinOffsets.contains(off) {
                    deferred.append(SIMD3<Float>(cupX, pinAboveWallCupY, off))
                }
            }
        }
    }
}
