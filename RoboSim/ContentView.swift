import SwiftUI
import RealityKit

// MARK: - Camera Mode

enum CameraMode {
    case thirdPerson
    case firstPerson
}

// MARK: - Follow Camera ECS

struct FollowCameraComponent: Component {
    static let behindDistance: Float = 0.6
    static let aboveDistance: Float = 0.3
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

// MARK: - Drive Input (shared between SwiftUI and RealityKit)

final class DriveInput: @unchecked Sendable {
    var forward: Float = 0
    var turn: Float = 0
}

// MARK: - Joystick View

enum JoystickAxis {
    case vertical
    case horizontal
}

struct JoystickView: View {
    @Binding var offset: CGSize
    var axis: JoystickAxis

    private let trackRadius: CGFloat = 60
    private let thumbSize: CGFloat = 44

    var body: some View {
        ZStack {
            Circle()
                .fill(.black.opacity(0.25))
                .frame(width: trackRadius * 2, height: trackRadius * 2)

            Circle()
                .fill(.white.opacity(0.8))
                .frame(width: thumbSize, height: thumbSize)
                .offset(clampedOffset)
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    offset = value.translation
                }
                .onEnded { _ in
                    offset = .zero
                }
        )
    }

    private var clampedOffset: CGSize {
        let x = axis == .horizontal ? offset.width : 0
        let y = axis == .vertical ? offset.height : 0
        let len = hypot(x, y)
        guard len > trackRadius else { return CGSize(width: x, height: y) }
        let scale = trackRadius / len
        return CGSize(width: x * scale, height: y * scale)
    }
}

// MARK: - Content View

struct ContentView: View {
    @State private var cameraMode: CameraMode = .thirdPerson
    @State private var leftStickOffset: CGSize = .zero
    @State private var rightStickOffset: CGSize = .zero
    @State private var driveInput = DriveInput()

    private static let thirdPersonPosition: SIMD3<Float> = [0, 5, 4]
    private static let joystickRadius: CGFloat = 60
    private static let maxLinearSpeed: Float = 1.5      // m/s
    private static let maxAngularSpeed: Float = 2.0     // rad/s
    private static let robotRadius: Float = 0.15
    private static let respawnThreshold: Float = -2
    private static let minCameraY: Float = 0.4          // keep orbit cam above the floor

    var body: some View {
        ZStack {
            RealityView { content in
                content.camera = .virtual

                FollowCameraSystem.registerSystem()
                FollowCameraComponent.registerComponent()

                // Shared frictionless material — robot drives via velocity targeting,
                // so friction isn't needed for propulsion and would only induce unwanted rolling.
                let frictionless = PhysicsMaterialResource.generate(friction: 0, restitution: 0)

                // --- FIELD (12' x 12' VEX tiles) ---
                let fieldSize: Float = 3.65
                let floorMesh = MeshResource.generatePlane(width: fieldSize, depth: fieldSize)
                let floorMaterial = SimpleMaterial(color: .darkGray, isMetallic: false)
                let floorEntity = ModelEntity(mesh: floorMesh, materials: [floorMaterial])

                let floorShape = ShapeResource.generateBox(size: [fieldSize, 0.01, fieldSize])
                floorEntity.components.set(PhysicsBodyComponent(shapes: [floorShape], mass: 0, material: frictionless, mode: .static))
                floorEntity.components.set(CollisionComponent(shapes: [floorShape]))
                content.add(floorEntity)

                // --- PERIMETER WALLS (invisible, keep robot on field) ---
                let wallHeight: Float = 0.3
                let wallThickness: Float = 0.05
                let halfField = fieldSize / 2
                let longShape = ShapeResource.generateBox(size: [fieldSize, wallHeight, wallThickness])
                let shortShape = ShapeResource.generateBox(size: [wallThickness, wallHeight, fieldSize])
                let walls: [(SIMD3<Float>, ShapeResource)] = [
                    ([0, wallHeight / 2, -halfField], longShape),
                    ([0, wallHeight / 2,  halfField], longShape),
                    ([-halfField, wallHeight / 2, 0], shortShape),
                    ([ halfField, wallHeight / 2, 0], shortShape),
                ]
                for (pos, shape) in walls {
                    let wall = Entity()
                    wall.position = pos
                    wall.components.set(PhysicsBodyComponent(shapes: [shape], mass: 0, material: frictionless, mode: .static))
                    wall.components.set(CollisionComponent(shapes: [shape]))
                    content.add(wall)
                }

                // --- ROBOT (sphere proxy — smooth rolling contact, no stick-slip) ---
                let robotRadius = Self.robotRadius
                let robotMesh = MeshResource.generateSphere(radius: robotRadius)
                let robotMaterial = SimpleMaterial(color: .red, isMetallic: true)
                let robotEntity = ModelEntity(mesh: robotMesh, materials: [robotMaterial])

                robotEntity.position = [0, robotRadius, 0]
                robotEntity.name = "VEX_Robot"

                let robotShape = ShapeResource.generateSphere(radius: robotRadius)
                robotEntity.components.set(PhysicsBodyComponent(shapes: [robotShape], mass: 2.0, material: frictionless, mode: .dynamic))
                robotEntity.components.set(CollisionComponent(shapes: [robotShape]))
                robotEntity.components.set(PhysicsMotionComponent())

                // Front-facing visual indicator (purely cosmetic — no physics)
                let indicatorMesh = MeshResource.generateBox(size: 0.05)
                let indicatorMaterial = SimpleMaterial(color: .white, isMetallic: false)
                let indicator = ModelEntity(mesh: indicatorMesh, materials: [indicatorMaterial])
                indicator.position = [0, 0, -robotRadius - 0.025]
                robotEntity.addChild(indicator)

                content.add(robotEntity)

                // --- CAMERA ---
                let cameraEntity = Entity()
                cameraEntity.name = "MainCamera"
                cameraEntity.look(at: .zero, from: Self.thirdPersonPosition, relativeTo: nil)
                cameraEntity.components.set(PerspectiveCameraComponent())
                content.add(cameraEntity)

                content.cameraTarget = floorEntity

                // --- LIGHTING ---
                let light = DirectionalLight()
                light.light.intensity = 5000
                light.look(at: [0, 0, 0], from: [2, 5, 2], relativeTo: nil)
                content.add(light)

                // --- DRIVE (velocity targeting + respawn) ---
                let input = driveInput
                _ = content.subscribe(to: SceneEvents.Update.self) { _ in
                    // Clamp orbit camera so it can't dip below the field
                    if cameraEntity.components[FollowCameraComponent.self] == nil {
                        var pos = cameraEntity.position(relativeTo: nil)
                        if pos.y < Self.minCameraY {
                            pos.y = Self.minCameraY
                            cameraEntity.look(at: .zero, from: pos, relativeTo: nil)
                        }
                    }

                    // Respawn if fallen off the field
                    if robotEntity.position(relativeTo: nil).y < Self.respawnThreshold {
                        robotEntity.components.remove(PhysicsBodyComponent.self)
                        robotEntity.components.remove(CollisionComponent.self)
                        robotEntity.components.remove(PhysicsMotionComponent.self)

                        robotEntity.position = [0, robotRadius, 0]
                        robotEntity.orientation = simd_quatf(angle: 0, axis: [0, 1, 0])

                        let shape = ShapeResource.generateSphere(radius: robotRadius)
                        robotEntity.components.set(CollisionComponent(shapes: [shape]))
                        robotEntity.components.set(PhysicsBodyComponent(shapes: [shape], mass: 2.0, material: frictionless, mode: .dynamic))
                        robotEntity.components.set(PhysicsMotionComponent())
                        return
                    }

                    // Command velocities directly. Preserve Y linear velocity so gravity still applies.
                    // Zeroing X/Z angular velocity locks pitch and roll → can't tip.
                    let robotForward = robotEntity.orientation(relativeTo: nil).act(SIMD3<Float>(0, 0, -1))
                    var motion = robotEntity.components[PhysicsMotionComponent.self] ?? PhysicsMotionComponent()
                    let currentY = motion.linearVelocity.y
                    let driveXZ = robotForward * (input.forward * Self.maxLinearSpeed)
                    motion.linearVelocity = SIMD3<Float>(driveXZ.x, currentY, driveXZ.z)
                    motion.angularVelocity = SIMD3<Float>(0, -input.turn * Self.maxAngularSpeed, 0)
                    robotEntity.components.set(motion)
                }
            } update: { content in
                var camera: Entity?
                for entity in content.entities {
                    if entity.name == "MainCamera" {
                        camera = entity
                        break
                    }
                }
                guard let camera else { return }

                switch cameraMode {
                case .thirdPerson:
                    if camera.components[FollowCameraComponent.self] != nil {
                        camera.components.remove(FollowCameraComponent.self)
                        camera.look(at: .zero, from: Self.thirdPersonPosition, relativeTo: nil)
                    }
                case .firstPerson:
                    if camera.components[FollowCameraComponent.self] == nil {
                        camera.components.set(FollowCameraComponent())
                    }
                }
            }
            .realityViewCameraControls(cameraMode == .thirdPerson ? .orbit : .none)
            .edgesIgnoringSafeArea(.all)

            // --- HUD ---
            VStack {
                HStack {
                    Spacer()
                    Button {
                        cameraMode = (cameraMode == .thirdPerson) ? .firstPerson : .thirdPerson
                    } label: {
                        Text(cameraMode == .thirdPerson ? "1st Person" : "3rd Person")
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(.ultraThinMaterial)
                            .cornerRadius(8)
                    }
                    .padding()
                }

                Spacer()

                HStack {
                    JoystickView(offset: $leftStickOffset, axis: .vertical)
                        .padding(30)
                    Spacer()
                    JoystickView(offset: $rightStickOffset, axis: .horizontal)
                        .padding(30)
                }
            }
        }
        .onChange(of: leftStickOffset) { _, newValue in
            driveInput.forward = max(-1, min(1, Float(-newValue.height / Self.joystickRadius)))
        }
        .onChange(of: rightStickOffset) { _, newValue in
            driveInput.turn = max(-1, min(1, Float(newValue.width / Self.joystickRadius)))
        }
    }
}
