import RealityKit
import UIKit

// Triangular-prism "rollers" sitting on top of each perimeter wall. Yellow
// on top, red on one side, blue on the other. They're physics-static — the
// robot can bump them visually but they don't move.
enum Toggles {

    @MainActor
    static func build(into fieldContainer: Entity,
                      surfaceMaterial: PhysicsMaterialResource) {
        let toggleLength: Float = 0.66
        let toggleSide: Float = 0.051562
        let sqrt3: Float = 1.7320508
        let toggleBBoxHalfHeight: Float = toggleSide * sqrt3 / 4
        // Bottom of toggle box sits on wall top (y = wallHeight)
        let toggleCenterY: Float = SimulationConstants.wallHeight + toggleBBoxHalfHeight + 0.025
        let halfField = SimulationConstants.halfField

        // N/S share the same Y-rotation, and E/W share the same Y-rotation
        // (translated, not mirrored). One side ends up red-inward and the
        // opposite side red-outward.
        let toggleConfigs: [(SIMD3<Float>, Float)] = [
            ([0, toggleCenterY,  halfField],  .pi / 2),   // N wall (red faces toward field)
            ([0, toggleCenterY, -halfField],  .pi / 2),   // S wall (same rotation as N)
            ([ halfField, toggleCenterY, 0],  0),         // E wall
            ([-halfField, toggleCenterY, 0],  0),         // W wall (same rotation as E)
        ]
        for (pos, yRot) in toggleConfigs {
            let t = makePrismToggle(toggleSide: toggleSide,
                                    toggleLength: toggleLength,
                                    sqrt3: sqrt3,
                                    surfaceMaterial: surfaceMaterial)
            t.position = pos
            t.orientation = simd_quatf(angle: yRot, axis: [0, 1, 0])
            fieldContainer.addChild(t)
        }
    }

    @MainActor
    private static func makePrismToggle(toggleSide s: Float,
                                        toggleLength L: Float,
                                        sqrt3: Float,
                                        surfaceMaterial: PhysicsMaterialResource) -> ModelEntity {
        let prism = ModelEntity()
        let yMat = SimpleMaterial(color: .yellow, isMetallic: false)
        let rMat = SimpleMaterial(color: .red, isMetallic: false)
        let bMat = SimpleMaterial(color: .blue, isMetallic: false)
        let supportMat = SimpleMaterial(color: .black, isMetallic: true)

        // Yellow top face
        let top = ModelEntity(mesh: .generatePlane(width: s, depth: L), materials: [yMat])
        top.position = [0, s * sqrt3 / 4, 0]
        prism.addChild(top)

        // Swap of red/blue so red faces outward from field on all 4 walls
        let left = ModelEntity(mesh: .generatePlane(width: s, depth: L), materials: [rMat])
        left.position = [-s / 4, 0, 0]
        left.orientation = simd_quatf(angle: 2 * .pi / 3, axis: [0, 0, 1])
        prism.addChild(left)

        let right = ModelEntity(mesh: .generatePlane(width: s, depth: L), materials: [bMat])
        right.position = [s / 4, 0, 0]
        right.orientation = simd_quatf(angle: -2 * .pi / 3, axis: [0, 0, 1])
        prism.addChild(right)

        // Black support brackets at each end of the long axis — toggle rotates on this axis
        let supportThick: Float = 0.012
        let supportWidth: Float = s * 0.7
        let supportHeight: Float = s * sqrt3 / 2 + 0.07
        for endZ: Float in [-L / 2 - supportThick / 2, L / 2 + supportThick / 2] {
            let support = ModelEntity(
                mesh: .generateBox(size: [supportWidth, supportHeight, supportThick]),
                materials: [supportMat]
            )
            support.position = [0, -0.02, endZ]
            prism.addChild(support)
        }

        let shape = ShapeResource.generateBox(size: [s, s * sqrt3 / 2, L])
        prism.components.set(PhysicsBodyComponent(shapes: [shape], mass: 0, material: surfaceMaterial, mode: .static))
        prism.components.set(CollisionComponent(shapes: [shape]))
        return prism
    }
}
