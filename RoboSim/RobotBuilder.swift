import RealityKit
import SwiftUI
import UIKit

// Builds the simple push-bot (chassis + 6 wheels + 4 motors + bumper) and
// installs the drive / respawn / orbit-camera-clamp update loop.
enum RobotBuilder {

    @MainActor
    static func build(surfaceMaterial: PhysicsMaterialResource) -> ModelEntity {
        let wheelRadius   = SimulationConstants.wheelRadius
        let chassisWidth  = SimulationConstants.chassisWidth
        let chassisHeight = SimulationConstants.chassisHeight
        let chassisLength = SimulationConstants.chassisLength
        let wheelThickness = SimulationConstants.wheelThickness

        // Parent — invisible, owns the single bounding-box collider
        let robotEntity = ModelEntity()
        robotEntity.position = [-1.5, wheelRadius, 0]
        robotEntity.name = "VEX_Robot"

        let robotShape = ShapeResource.generateBox(size: [
            chassisWidth + 2 * wheelThickness,
            2 * wheelRadius,
            chassisLength
        ])
        var robotBody = PhysicsBodyComponent(shapes: [robotShape], mass: 2.0, material: surfaceMaterial, mode: .dynamic)
        robotBody.angularDamping = 0.5   // bleed off stray pitch/roll over time
        robotEntity.components.set(robotBody)
        robotEntity.components.set(CollisionComponent(shapes: [robotShape]))
        robotEntity.components.set(PhysicsMotionComponent())

        // Chassis plate
        let chassisMesh = MeshResource.generateBox(size: [chassisWidth, chassisHeight, chassisLength])
        let chassisMat = SimpleMaterial(color: .gray, isMetallic: true)
        let chassis = ModelEntity(mesh: chassisMesh, materials: [chassisMat])
        chassis.position = [0, wheelRadius - chassisHeight / 2, 0]
        robotEntity.addChild(chassis)

        // Six wheels (3 per side)
        let wheelMesh = MeshResource.generateBox(size: [wheelThickness, 2 * wheelRadius, 2 * wheelRadius])
        let wheelMat = SimpleMaterial(color: .black, isMetallic: false)
        let sideX = chassisWidth / 2 + wheelThickness / 2
        let wheelZs: [Float] = [-chassisLength / 2 + wheelRadius, 0, chassisLength / 2 - wheelRadius]
        for x in [-sideX, sideX] {
            for z in wheelZs {
                let wheel = ModelEntity(mesh: wheelMesh, materials: [wheelMat])
                wheel.position = [x, 0, z]
                robotEntity.addChild(wheel)
            }
        }

        // Four drive motors (on top of chassis, near corners)
        let motorMesh = MeshResource.generateBox(size: [0.05, 0.04, 0.06])
        let motorMat = SimpleMaterial(color: .systemGreen, isMetallic: false)
        let motorY: Float = wheelRadius + 0.02
        for x: Float in [-chassisWidth / 4, chassisWidth / 4] {
            for z: Float in [-chassisLength / 3, chassisLength / 3] {
                let motor = ModelEntity(mesh: motorMesh, materials: [motorMat])
                motor.position = [x, motorY, z]
                robotEntity.addChild(motor)
            }
        }

        // Front bumper (heading indicator)
        let bumperMesh = MeshResource.generateBox(size: [chassisWidth * 0.6, 0.03, 0.03])
        let bumperMat = SimpleMaterial(color: .red, isMetallic: false)
        let bumper = ModelEntity(mesh: bumperMesh, materials: [bumperMat])
        bumper.position = [0, -wheelRadius + 0.02, -chassisLength / 2 - 0.015]
        robotEntity.addChild(bumper)

        return robotEntity
    }

    // Drive + respawn + orbit-camera-clamp update loop. Returns nothing —
    // the subscription is owned by `content` for its lifetime.
    @MainActor
    static func attachDriveLoop(content: RealityViewCameraContent,
                                robotEntity: ModelEntity,
                                cameraEntity: Entity,
                                input: DriveInput,
                                surfaceMaterial: PhysicsMaterialResource) {
        let wheelRadius    = SimulationConstants.wheelRadius
        let chassisWidth   = SimulationConstants.chassisWidth
        let chassisLength  = SimulationConstants.chassisLength
        let wheelThickness = SimulationConstants.wheelThickness

        _ = content.subscribe(to: SceneEvents.Update.self) { event in
            let dt = Float(event.deltaTime)
            // Clamp orbit camera so it can't dip below the field
            if cameraEntity.components[FollowCameraComponent.self] == nil {
                var pos = cameraEntity.position(relativeTo: nil)
                if pos.y < SimulationConstants.minCameraY {
                    pos.y = SimulationConstants.minCameraY
                    cameraEntity.look(at: .zero, from: pos, relativeTo: nil)
                }
            }

            // Respawn if fallen off the field
            if robotEntity.position(relativeTo: nil).y < SimulationConstants.respawnThreshold {
                robotEntity.components.remove(PhysicsBodyComponent.self)
                robotEntity.components.remove(CollisionComponent.self)
                robotEntity.components.remove(PhysicsMotionComponent.self)

                robotEntity.position = [-0.5, wheelRadius, 0.5]
                robotEntity.orientation = simd_quatf(angle: 0, axis: [0, 1, 0])

                let shape = ShapeResource.generateBox(size: [
                    chassisWidth + 2 * wheelThickness,
                    2 * wheelRadius,
                    chassisLength
                ])
                robotEntity.components.set(CollisionComponent(shapes: [shape]))
                var respawnBody = PhysicsBodyComponent(shapes: [shape], mass: 2.0, material: surfaceMaterial, mode: .dynamic)
                respawnBody.angularDamping = 0.5
                robotEntity.components.set(respawnBody)
                robotEntity.components.set(PhysicsMotionComponent())
                return
            }

            // Drive with momentum + tip dynamics.
            let orientation = robotEntity.orientation(relativeTo: nil)
            let robotForward = orientation.act(SIMD3<Float>(0, 0, -1))
            let robotUp = orientation.act(SIMD3<Float>(0, 1, 0))

            var motion = robotEntity.components[PhysicsMotionComponent.self] ?? PhysicsMotionComponent()
            let currentY = motion.linearVelocity.y

            // While reasonably upright, override velocity to enact joystick input.
            // Once tipped past ~65° we hand control back to physics so the robot
            // can actually fall over and slide on the ground.
            if robotUp.y > 0.4 {
                // Project forward onto the horizontal plane so the drive command
                // never pushes the robot up/down when it's leaning.
                var horizForward = SIMD3<Float>(robotForward.x, 0, robotForward.z)
                let horizLen = simd_length(horizForward)
                horizForward = horizLen > 1e-4 ? horizForward / horizLen : SIMD3<Float>(0, 0, -1)

                let targetForwardSpeed = input.forward * SimulationConstants.maxLinearSpeed
                let currentLinearXZ = SIMD3<Float>(motion.linearVelocity.x, 0, motion.linearVelocity.z)
                let currentForwardSpeed = simd_dot(currentLinearXZ, horizForward)
                let speedDelta = targetForwardSpeed - currentForwardSpeed

                // Constant-acceleration ramp toward target speed: velocity
                // climbs linearly until it reaches the joystick-commanded
                // cap, then holds — not the exponential ease-in we had before.
                let maxLinearAccel: Float = 5.0   // m/s²
                let speedStep = max(-maxLinearAccel * dt, min(maxLinearAccel * dt, speedDelta))
                let newForwardSpeed = currentForwardSpeed + speedStep
                let newLinearXZ = horizForward * newForwardSpeed
                motion.linearVelocity = SIMD3<Float>(newLinearXZ.x, currentY, newLinearXZ.z)

                var ang = motion.angularVelocity

                // Aggressive deceleration / reversal → pitch impulse in the
                // direction of current motion (forward momentum tips the bot
                // forward when motors slam reverse).
                if abs(currentForwardSpeed) > 0.3 && abs(speedDelta) > 0.8 {
                    let robotRight = orientation.act(SIMD3<Float>(1, 0, 0))
                    let tipSign: Float = currentForwardSpeed > 0 ? -1 : 1
                    let tipRate: Float = 8.0
                    ang += robotRight * (tipSign * tipRate * dt)
                }

                // Turn rate falls off the faster you're driving — full-yaw only
                // when stopped, ~40% of max yaw at full forward/back.
                let turnScale: Float = 1.0 - 0.6 * abs(input.forward)
                ang.y = -input.turn * SimulationConstants.maxAngularSpeed * turnScale

                motion.angularVelocity = ang
            }

            robotEntity.components.set(motion)
        }
    }
}
