import RealityKit

// Pin/cup rows on top of the alliance-colored loader platforms outside the
// W/E walls. Layout (top-down, edge of loader → toward field):
//   back row :  A  ......... Y ......... A     (2 alliance + 1 yellow)
//   pin row  :  P P P P P P P P P P              (10 alliance pins)
//   cup row  :  C C C C C C C C C C              (10 cups)
enum LoaderRowPlacements {

    static func add(pins: inout [Placements.PinPlacement],
                    cups: inout [Placements.CupPlacement],
                    platform: LoadingZones.PlatformGeometry) {
        let loaderSpawnY: Float = platform.topY + 0.15  // pin drop height
        let cupOnLoaderY: Float = platform.topY + 0.15  // cup spawn on loader

        let backRowXOffset: Float =  0.20    // A Y A row, away from the field
        let pinRowXOffset:  Float =  0.00    // 10 alliance pins, middle of platform
        let cupRowXOffset:  Float = -0.20    // 10 cups, toward the field

        // 10 evenly-spaced Z positions for the pin / cup rows.
        let rowSpacingZ: Float = 0.15
        let pinRowZ: [Float] = (0..<10).map { (Float($0) - 4.5) * rowSpacingZ }
        let cupRowZ: [Float] = pinRowZ

        // Back row: 2 alliance pins at platform extremes + 1 yellow centered.
        let backAllianceZ: [Float] = [-1.2, 1.2]
        let backYellowZ:   Float   =  0.0

        struct MatchLoadSide {
            let platformX: Float
            let alliance:  PinHalfColor
            let frontDir:  Float          // +1 = field is at +X, -1 = field is at -X
        }
        let matchLoadSides: [MatchLoadSide] = [
            MatchLoadSide(platformX: platform.westCenterX, alliance: .red,  frontDir:  1),
            MatchLoadSide(platformX: platform.eastCenterX, alliance: .blue, frontDir: -1),
        ]

        for side in matchLoadSides {
            // --- Back row: A Y A ---------------------------------------
            let backX = side.platformX + backRowXOffset * side.frontDir
            for z in backAllianceZ {
                pins.append((SIMD3<Float>(backX, loaderSpawnY, z), side.alliance, .yellow, .vertical))
            }
            // 1 yellow/yellow pin centered between them (decor only).
            pins.append((SIMD3<Float>(backX, loaderSpawnY, backYellowZ), .yellow, .yellow, .vertical))

            // --- Middle row: 10 alliance pins --------------------------
            let pinX = side.platformX + pinRowXOffset * side.frontDir
            for z in pinRowZ {
                pins.append((SIMD3<Float>(pinX, loaderSpawnY, z), side.alliance, .yellow, .vertical))
            }

            // --- Front row: 10 cups (toward the field) -----------------
            let cupX = side.platformX + cupRowXOffset * side.frontDir
            for z in cupRowZ {
                cups.append((SIMD3<Float>(cupX, cupOnLoaderY, z), false))
            }
        }
    }
}
