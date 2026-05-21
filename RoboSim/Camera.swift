import RealityKit

// MARK: - Camera Mode

enum CameraMode {
    case thirdPerson
    case firstPerson
}

// MARK: - Follow Camera ECS

struct FollowCameraComponent: Component {
    static let behindDistance: Float = 0.6
    static let aboveDistance: Float = 0.6
}

class FollowCameraSystem: System {
    private static let cameraQuery = EntityQuery(where: .has(FollowCameraComponent.self))

    required init(scene: RealityKit.Scene) {}

    func update(context: SceneUpdateContext) {
        guard let robot = context.scene.findEntity(named: "VEX_Robot") else { return }

        for cameraEntity in context.entities(matching: Self.cameraQuery, updatingSystemWhen: .rendering) {
            let robotPosition = robot.position(relativeTo: nil)
            let robotRotation = robot.orientation(relativeTo: nil)

            let localOffset = SIMD3<Float>(0, FollowCameraComponent.aboveDistance, FollowCameraComponent.behindDistance)
            let worldOffset = robotRotation.act(localOffset)
            cameraEntity.look(at: robotPosition, from: robotPosition + worldOffset, relativeTo: nil)
        }
    }
}
