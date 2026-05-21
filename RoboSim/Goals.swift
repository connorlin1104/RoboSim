import RealityKit
import UIKit

// Builds the 1 tall neutral + 4 short neutral + 2 red alliance + 2 blue
// alliance goals. Reds line the west side of the SINGLE (NW-SE) line, blues
// line the east side; the short neutrals straddle the DOUBLE (NE-SW) line.
enum Goals {

    @MainActor
    static func build(into fieldContainer: Entity,
                      surfaceMaterial: PhysicsMaterialResource) {
        let neutralGoalMat = SimpleMaterial(color: .lightGray, isMetallic: true)
        let redGoalMat = SimpleMaterial(color: .red, isMetallic: true)
        let blueGoalMat = SimpleMaterial(color: .blue, isMetallic: true)
        let goalFootprint: Float = 0.142494
        let allianceGoalSize: SIMD3<Float> = [goalFootprint, 0.08255,   goalFootprint]
        let shortGoalSize:    SIMD3<Float> = [goalFootprint, 0.146558,  goalFootprint]
        let tallGoalSize:     SIMD3<Float> = [goalFootprint, 0.222758,  goalFootprint]
        let goalFar:  Float = 1.2   // outer ring distance from center
        let goalNear: Float = 0.6   // inner ring distance from center
        let shortY = shortGoalSize.y / 2

        let goals: [(SIMD3<Float>, SIMD3<Float>, SimpleMaterial)] = [
            // Tall neutral goal — center Midfield
            (tallGoalSize, [0, tallGoalSize.y / 2, 0], neutralGoalMat),
            // 4 short neutral — straddling the DOUBLE line (NE-SW diagonal), 2 per side
            (shortGoalSize, [-goalFar,  shortY, -goalNear], neutralGoalMat),  // NW side
            (shortGoalSize, [-goalNear, shortY, -goalFar],  neutralGoalMat),  // NW side
            (shortGoalSize, [ goalFar,  shortY,  goalNear], neutralGoalMat),  // SE side
            (shortGoalSize, [ goalNear, shortY,  goalFar],  neutralGoalMat),  // SE side
            // 2 red alliance goals — SW side of the SINGLE line (NW-SE diagonal)
            (allianceGoalSize, [-goalFar,  shortY,  goalNear], redGoalMat),
            (allianceGoalSize, [-goalNear, shortY,  goalFar],  redGoalMat),
            // 2 blue alliance goals — NE side of the SINGLE line
            (allianceGoalSize, [ goalFar,  shortY, -goalNear], blueGoalMat),
            (allianceGoalSize, [ goalNear, shortY, -goalFar],  blueGoalMat),
        ]
        for goalData in goals {
            let size = goalData.0
            let pos = goalData.1
            let mat = goalData.2

            let mesh = MeshResource.generateBox(size: size)
            let shape = ShapeResource.generateBox(size: size)

            let goal = ModelEntity()
            goal.model = ModelComponent(mesh: mesh, materials: [mat])
            goal.position = pos

            let physicsBody = PhysicsBodyComponent(shapes: [shape], mass: 0, material: surfaceMaterial, mode: .static)
            let collision = CollisionComponent(shapes: [shape])

            goal.components.set(physicsBody)
            goal.components.set(collision)

            fieldContainer.addChild(goal)
        }
    }
}
