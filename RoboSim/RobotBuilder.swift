import RealityKit
import SwiftUI
import UIKit

// Builds the simple push-bot (chassis + 6 wheels + 4 motors + bumper + arm)
// and installs the drive / respawn / orbit-camera-clamp update loop.
enum RobotBuilder {

    // Names exposed so the drive loop can pick the arm + roller out of the
    // hierarchy without re-walking the tree every frame.
    static let armPivotName  = "VEX_ArmPivot"
    static let intakeRollerName = "VEX_IntakeRoller"

    // Compound collision shape = chassis box + arm/roller envelope rotated
    // around the pivot by the current arm angle. We rebuild this every frame
    // so the collider tracks the arm's actual orientation — arm-up gives a
    // tall vertical extension (chassis can drive to walls); arm-down gives a
    // forward-projecting extension (arm tip stops at walls, roller touches
    // wall-mounted field rollers).
    @MainActor
    static func compoundRobotShape(armAngle: Float) -> [ShapeResource] {
        let wheelRadius    = SimulationConstants.wheelRadius
        let chassisWidth   = SimulationConstants.chassisWidth
        let chassisLength  = SimulationConstants.chassisLength
        let wheelThickness = SimulationConstants.wheelThickness
        let armLength      = SimulationConstants.armLength
        let armThick       = SimulationConstants.armBarThickness
        let pivotY         = SimulationConstants.armPivotHeight
        let pivotZ         = SimulationConstants.armPivotForwardOffset
        let rollerR        = SimulationConstants.intakeRollerRadius
        let rollerLen      = SimulationConstants.intakeRollerLength

        let chassisShape = ShapeResource.generateBox(size: [
            chassisWidth + 2 * wheelThickness,
            2 * wheelRadius,
            chassisLength
        ])

        // Build the arm+roller envelope as a single box in its rest pose
        // (extending from pivot toward -Z), then translate+rotate it into
        // place at the pivot, rotated around local X by armAngle.
        let envWidth  = max(chassisWidth * 0.55, rollerLen)
        let envHeight = max(armThick * 2, rollerR * 2)
        let envDepth  = armLength + rollerR
        let envBox = ShapeResource
            .generateBox(size: [envWidth, envHeight, envDepth])
            .offsetBy(translation: [0, 0, -envDepth / 2])  // back end → origin

        let armEnvelope = envBox.offsetBy(
            rotation: simd_quatf(angle: armAngle, axis: [1, 0, 0]),
            translation: [0, pivotY, pivotZ]
        )

        return [chassisShape, armEnvelope]
    }

    @MainActor
    static func build(surfaceMaterial: PhysicsMaterialResource) -> ModelEntity {
        let wheelRadius   = SimulationConstants.wheelRadius
        let chassisWidth  = SimulationConstants.chassisWidth
        let chassisHeight = SimulationConstants.chassisHeight
        let chassisLength = SimulationConstants.chassisLength
        let wheelThickness = SimulationConstants.wheelThickness

        // Parent — invisible, owns the compound collider. Compound shape =
        // chassis box + a forward "arm sweep" box that envelopes the volume
        // the arm can swing through. The arm/roller themselves are visual
        // children with CollisionComponents but no PhysicsBody, so they
        // don't physically participate; this extra forward shape on the
        // dynamic body is what actually blocks walls when the bot drives at
        // them with the arm extended.
        let robotEntity = ModelEntity()
        robotEntity.position = [-1.5, wheelRadius, 0]
        robotEntity.name = "VEX_Robot"

        // PhysicsBody keeps a stable shape (just the chassis) for mass/
        // inertia — animating the inertia tensor each frame causes
        // weird wobble. CollisionComponent uses the dynamic compound and
        // gets refreshed every frame from the drive loop.
        let initialShapes = compoundRobotShape(armAngle: SimulationConstants.armMinAngle)
        var robotBody = PhysicsBodyComponent(shapes: [initialShapes[0]], mass: 2.0, material: surfaceMaterial, mode: .dynamic)
        robotBody.angularDamping = 0.5   // bleed off stray pitch/roll over time
        robotEntity.components.set(robotBody)
        robotEntity.components.set(CollisionComponent(shapes: initialShapes))
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

        // --- Arm assembly ---------------------------------------------------
        // Pivot sits on top of the chassis at the front. Rotating the pivot
        // around X swings the upper arm forward/up. The upper arm and intake
        // roller live as children of the pivot so a single rotation moves
        // everything.
        let pivot = Entity()
        pivot.name = armPivotName
        pivot.position = [
            0,
            SimulationConstants.armPivotHeight,
            SimulationConstants.armPivotForwardOffset
        ]
        // Start with arm slightly raised (resting just above horizontal).
        pivot.orientation = simd_quatf(angle: SimulationConstants.armMinAngle, axis: [1, 0, 0])
        robotEntity.addChild(pivot)

        let armLen = SimulationConstants.armLength
        let armThick = SimulationConstants.armBarThickness
        let upperMesh = MeshResource.generateBox(size: [chassisWidth * 0.55, armThick, armLen])
        let armMat = SimpleMaterial(color: .systemGray2, isMetallic: true)
        let upperArm = ModelEntity(mesh: upperMesh, materials: [armMat])
        // Centered along -Z so it extends forward from the pivot.
        upperArm.position = [0, 0, -armLen / 2]
        pivot.addChild(upperArm)

        // Intake roller — a cylinder at the tip of the upper arm. Has its own
        // collider so it physically contacts field rollers and pins; visual
        // spin is driven by the per-frame update.
        let rollerMesh = MeshResource.generateCylinder(
            height: SimulationConstants.intakeRollerLength,
            radius: SimulationConstants.intakeRollerRadius
        )
        let rollerMat = SimpleMaterial(color: .systemOrange, isMetallic: false)
        let roller = ModelEntity(mesh: rollerMesh, materials: [rollerMat])
        roller.name = intakeRollerName
        // Cylinder long axis is Y; we want it across the arm (X axis), so
        // rotate 90° around Z.
        roller.orientation = simd_quatf(angle: .pi / 2, axis: [0, 0, 1])
        roller.position = [0, 0, -armLen]
        let rollerShape = ShapeResource.generateCapsule(
            height: SimulationConstants.intakeRollerLength,
            radius: SimulationConstants.intakeRollerRadius
        )
        roller.components.set(CollisionComponent(shapes: [rollerShape]))
        pivot.addChild(roller)

        // Visible spin markers — two perpendicular contrasting fins poking
        // out from the cylinder. With one fin and a smooth-shaded cylinder
        // the spin was easy to miss at third-person camera distance; two
        // fins of contrasting colors mean *something* visible is moving no
        // matter the viewing angle.
        let r = SimulationConstants.intakeRollerRadius
        let finAxial: Float    = SimulationConstants.intakeRollerLength * 0.92
        let finRadial: Float   = r * 0.9                 // how far it sticks out
        let finTangent: Float  = r * 0.3                 // thickness in spin direction
        let finOffset = r + finRadial / 2

        // Fin 1 — black, along local +Z.
        let finZMesh = MeshResource.generateBox(size: [finTangent, finAxial, finRadial])
        let finZ = ModelEntity(mesh: finZMesh, materials: [
            SimpleMaterial(color: .black, isMetallic: false)
        ])
        finZ.position = [0, 0, finOffset]
        roller.addChild(finZ)

        // Fin 2 — yellow, along local +X, perpendicular to Fin 1.
        let finXMesh = MeshResource.generateBox(size: [finRadial, finAxial, finTangent])
        let finX = ModelEntity(mesh: finXMesh, materials: [
            SimpleMaterial(color: .yellow, isMetallic: false)
        ])
        finX.position = [finOffset, 0, 0]
        roller.addChild(finX)

        return robotEntity
    }

    // Drive + respawn + orbit-camera-clamp update loop. Returns nothing —
    // the subscription is owned by `content` for its lifetime.
    @MainActor
    static func attachDriveLoop(content: RealityViewCameraContent,
                                robotEntity: ModelEntity,
                                cameraEntity: Entity,
                                input: DriveInput,
                                surfaceMaterial: PhysicsMaterialResource,
                                matchLoaderLifter: FieldRuntime.MatchLoaderLifter?) {
        let wheelRadius    = SimulationConstants.wheelRadius
        let chassisWidth   = SimulationConstants.chassisWidth
        let chassisLength  = SimulationConstants.chassisLength
        let wheelThickness = SimulationConstants.wheelThickness

        let armPivot = robotEntity.findEntity(named: armPivotName)
        let intakeRoller = robotEntity.findEntity(named: intakeRollerName)
        var armAngle: Float = SimulationConstants.armMinAngle
        var rollerSpin: Float = 0

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

                let shapes = compoundRobotShape(armAngle: armAngle)
                robotEntity.components.set(CollisionComponent(shapes: shapes))
                var respawnBody = PhysicsBodyComponent(shapes: [shapes[0]], mass: 2.0, material: surfaceMaterial, mode: .dynamic)
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

            // --- Arm + intake -----------------------------------------------
            // Hold-to-move with release-stays-put: X raises while held, A
            // lowers while held, neither held → arm freezes at the current
            // angle. Both held cancel out, again leaving the arm still.
            if let pivot = armPivot {
                let dir: Float = (input.armUp ? 1 : 0) - (input.armDown ? 1 : 0)
                if dir != 0 {
                    let prev = armAngle
                    armAngle += dir * SimulationConstants.armSlewRate * dt
                    armAngle = min(SimulationConstants.armMaxAngle,
                                   max(SimulationConstants.armMinAngle, armAngle))
                    // Refresh the chassis-side collider so it tracks the
                    // arm. Skip if the angle didn't move (button held but
                    // already pinned at min/max) to avoid useless work.
                    if armAngle != prev {
                        robotEntity.components.set(CollisionComponent(
                            shapes: compoundRobotShape(armAngle: armAngle)
                        ))
                    }
                }
                pivot.orientation = simd_quatf(angle: armAngle, axis: [1, 0, 0])
            }

            if let roller = intakeRoller {
                let dir: Float = (input.intakeIn ? 1 : 0) - (input.intakeOut ? 1 : 0)
                rollerSpin += dir * SimulationConstants.intakeSpinRate * dt
                // Roller's cylinder long axis is local Y (it was rotated 90°
                // around Z to lie across the arm). Spin around local Y.
                let crossArmSpin = simd_quatf(angle: rollerSpin, axis: [0, 1, 0])
                let crossArmMount = simd_quatf(angle: .pi / 2, axis: [0, 0, 1])
                roller.orientation = crossArmMount * crossArmSpin
            }

            // --- Matchloader lift (alliance tape proximity) ------------------
            if let lifter = matchLoaderLifter {
                lifter.tick(dt: dt, robotWorldPosition: robotEntity.position(relativeTo: nil))
            }
        }
    }
}
