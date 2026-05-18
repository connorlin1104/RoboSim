import SwiftUI
import RealityKit
import RoboticsSimulationAssets

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

// MARK: - Pin Colors

// rawValue must match the asset filename prefix exactly, e.g.
// (top: .red, bottom: .blue) → "RedBluePin.usdz".
enum PinHalfColor: String {
    case red = "Red"
    case blue = "Blue"
    case yellow = "Yellow"
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
    
    private static let thirdPersonPosition: SIMD3<Float> = [-3, 4, 3]   // NW perspective
    private static let joystickRadius: CGFloat = 60
    private static let maxLinearSpeed: Float = 1.0      // m/s
    private static let maxAngularSpeed: Float = 2.0     // rad/s
    private static let wheelRadius: Float = 0.06        // also = robot half-height
    private static let chassisWidth: Float = 0.3
    private static let chassisHeight: Float = 0.08
    private static let chassisLength: Float = 0.4
    private static let wheelThickness: Float = 0.04
    private static let respawnThreshold: Float = -2
    private static let minCameraY: Float = 0.4          // keep orbit cam above the floor
    
    var body: some View {
        ZStack {
            RealityView { content in
                content.camera = .virtual
                
                FollowCameraSystem.registerSystem()
                FollowCameraComponent.registerComponent()
                
                // Shared surface material — gives the floor/walls grip so loose game
                // pieces settle. The robot ignores friction while upright because its
                // velocity is set directly each frame; once tipped it falls back on
                // physics + this friction to stop sliding.
                let surfaceMaterial = PhysicsMaterialResource.generate(friction: 0.5, restitution: 0)
                
                await setupRoboticsField(content: &content)
                
                // --- ROBOT (simple push bot: chassis + 6 wheels + 4 motors) ---
                let wheelRadius = Self.wheelRadius
                let chassisWidth = Self.chassisWidth
                let chassisHeight = Self.chassisHeight
                let chassisLength = Self.chassisLength
                let wheelThickness = Self.wheelThickness
                
                // Parent — invisible, owns the single bounding-box collider
                let robotEntity = ModelEntity()
                robotEntity.position = [-0.5, wheelRadius, 0.5]
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
                
                content.add(robotEntity)
                
                // --- CAMERA ---
                let cameraEntity = Entity()
                cameraEntity.name = "MainCamera"
                cameraEntity.look(at: .zero, from: Self.thirdPersonPosition, relativeTo: nil)
                cameraEntity.components.set(PerspectiveCameraComponent())
                content.add(cameraEntity)

                // --- LIGHTING ---
                let light = DirectionalLight()
                light.light.intensity = 5000
                light.look(at: [0, 0, 0], from: [2, 5, 2], relativeTo: nil)
                content.add(light)
                
                // --- DRIVE (velocity targeting + respawn) ---
                let input = driveInput
                _ = content.subscribe(to: SceneEvents.Update.self) { event in
                    let dt = Float(event.deltaTime)
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

                        let targetForwardSpeed = input.forward * Self.maxLinearSpeed
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
                        ang.y = -input.turn * Self.maxAngularSpeed * turnScale

                        motion.angularVelocity = ang
                    }

                    robotEntity.components.set(motion)
                }
            } update: { content in
                // Explicitly define the closure argument type ($0: Entity) to stop the type-checker from guessing
                let mainCamera = content.entities.first(where: { ($0 as Entity).name == "MainCamera" })
                
                guard let camera = mainCamera else { return }
                
                // 2. Pull the component check out of the switch statement completely
                let hasFollowComponent = camera.components[FollowCameraComponent.self] != nil
                
                switch cameraMode {
                case .thirdPerson:
                    if hasFollowComponent {
                        camera.components.remove(FollowCameraComponent.self)
                        camera.look(at: .zero, from: Self.thirdPersonPosition, relativeTo: nil)
                    }
                case .firstPerson:
                    // 3. Use the pre-calculated boolean here so the compiler does zero work inside the case
                    if !hasFollowComponent {
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
                        .padding(.leading, 100)
                        .padding(.bottom, 90)
                    Spacer()
                    JoystickView(offset: $rightStickOffset, axis: .horizontal)
                        .padding(.trailing, 100)
                        .padding(.bottom, 90)
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
    #if os(iOS) || os(macOS)
    @MainActor
    func setupRoboticsField(content: inout RealityViewCameraContent) async {

        let fieldContainer = Entity()
        // Shared surface material — gives the floor/walls grip so loose game
        // pieces settle. The robot ignores friction while upright because its
        // velocity is set directly each frame; once tipped it falls back on
        // physics + this friction to stop sliding.
        let surfaceMaterial = PhysicsMaterialResource.generate(friction: 0.5, restitution: 0)
        
        // --- FIELD (12' x 12' VEX tiles, alternating gray checkerboard) ---
        let fieldSize: Float = 3.65
        let floorMesh = MeshResource.generatePlane(width: fieldSize, depth: fieldSize)
        let darkTileMat = SimpleMaterial(color: UIColor(white: 0.32, alpha: 1), isMetallic: false)
        let lightTileMat = SimpleMaterial(color: UIColor(white: 0.36, alpha: 1), isMetallic: false)
        let floorEntity = ModelEntity(mesh: floorMesh, materials: [darkTileMat])
        
        let floorShape = ShapeResource.generateBox(size: [fieldSize, 0.01, fieldSize])
        floorEntity.components.set(PhysicsBodyComponent(shapes: [floorShape], mass: 0, material: surfaceMaterial, mode: .static))
        floorEntity.components.set(CollisionComponent(shapes: [floorShape]))
        fieldContainer.addChild(floorEntity)
        
        // 6x6 tile checkerboard overlay (light tiles on top of dark base)
        let floorTileSize: Float = fieldSize / 6
        let tileMesh = MeshResource.generatePlane(width: floorTileSize, depth: floorTileSize)
        
        let startOffset = -fieldSize / 2 + floorTileSize / 2
        
        for i in 0..<6 {
            for j in 0..<6 {
                // Moving the filter inside an explicit 'if' breaks the compiler gridlock completely
                if (i + j) % 2 == 0 {
                    let xPos = startOffset + (Float(i) * floorTileSize)
                    let zPos = startOffset + (Float(j) * floorTileSize)
                    
                    let tile = ModelEntity()
                    tile.model = ModelComponent(mesh: tileMesh, materials: [lightTileMat])
                    tile.position = SIMD3<Float>(xPos, 0.001, zPos)
                    
                    fieldContainer.addChild(tile)
                }
            }
        }
        
        // --- PERIMETER WALLS (VEX-style, visible) ---
        let wallHeight: Float = 0.3
        let wallThickness: Float = 0.05
        let halfField = fieldSize / 2
        let longSize: SIMD3<Float> = [fieldSize, wallHeight, wallThickness]
        let shortSize: SIMD3<Float> = [wallThickness, wallHeight, fieldSize]
        let longShape = ShapeResource.generateBox(size: longSize)
        let shortShape = ShapeResource.generateBox(size: shortSize)
        let longMesh = MeshResource.generateBox(size: longSize)
        let shortMesh = MeshResource.generateBox(size: shortSize)
        let wallMaterial = SimpleMaterial(color: .white, isMetallic: false)
        let walls: [(SIMD3<Float>, ShapeResource, MeshResource)] = [
            ([0, wallHeight / 2, -halfField], longShape, longMesh),
            ([0, wallHeight / 2,  halfField], longShape, longMesh),
            ([-halfField, wallHeight / 2, 0], shortShape, shortMesh),
            ([ halfField, wallHeight / 2, 0], shortShape, shortMesh),
        ]
        for (pos, shape, mesh) in walls {
            let wall = ModelEntity(mesh: mesh, materials: [wallMaterial])
            wall.position = pos
            wall.components.set(PhysicsBodyComponent(shapes: [shape], mass: 0, material: surfaceMaterial, mode: .static))
            wall.components.set(CollisionComponent(shapes: [shape]))
            fieldContainer.addChild(wall)
        }
        
        // Corner posts (dark gray, slightly taller than walls)
        let postSize: SIMD3<Float> = [wallThickness * 1.5, wallHeight * 1.1, wallThickness * 1.5]
        let postMesh = MeshResource.generateBox(size: postSize)
        let postMaterial = SimpleMaterial(color: .darkGray, isMetallic: true)
        for x in [-halfField, halfField] {
            for z in [-halfField, halfField] {
                let post = ModelEntity(mesh: postMesh, materials: [postMaterial])
                post.position = [x, postSize.y / 2, z]
                fieldContainer.addChild(post)
            }
        }
        
        // --- CENTRAL DIAMOND (Midfield zone — vertices at N/E/S/W of center) ---
        let lineMat = SimpleMaterial(color: .white, isMetallic: false)
        let stripeWidth: Float = 0.025
        let diamondRadius: Float = 0.6
        let dr = diamondRadius
        
        // 1. Force the square root to happen natively as a Float from the beginning
        let sqrtTwo = Float(2.0).squareRoot()
        let diamondSide: Float = diamondRadius * sqrtTwo
        
        // 2. Define a clean struct to bypass tuple type inference stress
        struct DiamondEdgeSpec { let pos: SIMD3<Float>; let angle: Float }
        
        let diamondEdges: [DiamondEdgeSpec] = [
            DiamondEdgeSpec(pos: SIMD3<Float>( dr / 2, 0.002,  dr / 2), angle: 3 * .pi / 4),
            DiamondEdgeSpec(pos: SIMD3<Float>( dr / 2, 0.002, -dr / 2), angle: .pi / 4),
            DiamondEdgeSpec(pos: SIMD3<Float>(-dr / 2, 0.002, -dr / 2), angle: 3 * .pi / 4),
            DiamondEdgeSpec(pos: SIMD3<Float>(-dr / 2, 0.002,  dr / 2), angle: .pi / 4),
        ]
        
        for spec in diamondEdges {
            let mesh = MeshResource.generatePlane(width: stripeWidth, depth: diamondSide)
            
            // 3. Break model creation into separate lines
            let edge = ModelEntity()
            edge.model = ModelComponent(mesh: mesh, materials: [lineMat])
            edge.position = spec.pos
            edge.orientation = simd_quatf(angle: spec.angle, axis: SIMD3<Float>(0, 1, 0))
            
            fieldContainer.addChild(edge)
        }
        
        // --- DIAGONAL LINES — corner-side → diamond, stopping short of the L tape ---
        // NW-SE diagonal: SINGLE stripe (in 2 segments)
        // NE-SW diagonal: DOUBLE stripe (in 2 segments)
        // The L tape's vertical leg's "inner" end is at |z| = halfField - 0.5 * 1.0225 * tileSize. Stop the diagonal
        // at the matching point on the line z = ±x so it never crosses the L colored lines.
        let diagStopAbs: Float = halfField - 0.5 * 1.03 * (fieldSize / 6)
        
        
        // Keep the line math completely flat and uniform
        let segLength: Float = sqrtTwo * (diagStopAbs - (diamondRadius / 2))
        let segOff: Float = (diagStopAbs + (diamondRadius / 2)) / 2
        
        // Single-striped NW-SE segments (NW corner→NW diamond vertex, SE corner→SE diamond vertex)
        let singleSegMids: [SIMD3<Float>] = [
            [-segOff, 0.002,  segOff],   // NW
            [ segOff, 0.002, -segOff],   // SE
        ]
        for mid in singleSegMids {
            let mesh = MeshResource.generatePlane(width: stripeWidth, depth: segLength)
            let strip = ModelEntity(mesh: mesh, materials: [lineMat])
            strip.position = mid
            strip.orientation = simd_quatf(angle: -.pi / 4, axis: [0, 1, 0])
            fieldContainer.addChild(strip)
        }
        // Double-striped NE-SW segments
        let doubleSegMids: [SIMD3<Float>] = [
            [ segOff, 0.002,  segOff],   // NE
            [-segOff, 0.002, -segOff],   // SW
        ]
        let perpNWSE = simd_normalize(SIMD3<Float>(1, 0, -1))   // perpendicular to NE-SW direction
        for mid in doubleSegMids {
            for stripeOff: Float in [-0.025, 0.025] {
                let mesh = MeshResource.generatePlane(width: stripeWidth, depth: segLength)
                let strip = ModelEntity(mesh: mesh, materials: [lineMat])
                strip.position = mid + perpNWSE * stripeOff
                strip.orientation = simd_quatf(angle: .pi / 4, axis: [0, 1, 0])
                fieldContainer.addChild(strip)
            }
        }
        
        // --- GOALS (1 tall + 4 short neutral, 2 red on W + 2 blue on E) ---
        // Alliances: red along west wall, blue along east wall
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
            // 1. Decompose the tuple on separate, simple lines
            let size = goalData.0
            let pos = goalData.1
            let mat = goalData.2
            
            // 2. Generate the resources step-by-step
            let mesh = MeshResource.generateBox(size: size)
            let shape = ShapeResource.generateBox(size: size)
            
            // 3. Initialize a blank ModelEntity first to keep the compiler happy
            let goal = ModelEntity()
            goal.model = ModelComponent(mesh: mesh, materials: [mat])
            goal.position = pos
            
            // 4. Configure physics and collision separately
            let physicsBody = PhysicsBodyComponent(shapes: [shape], mass: 0, material: surfaceMaterial, mode: .static)
            let collision = CollisionComponent(shapes: [shape])
            
            goal.components.set(physicsBody)
            goal.components.set(collision)
            
            fieldContainer.addChild(goal)
        }
        
        // --- TOGGLES (triangular-prism "rollers" sitting on top of the perimeter walls) ---
        let toggleLength: Float = 0.66
        let toggleSide: Float = 0.051562
        let sqrt3: Float = 1.7320508
        let toggleBBoxHalfHeight: Float = toggleSide * sqrt3 / 4
        // Bottom of toggle box sits on wall top (y = wallHeight)
        let toggleCenterY: Float = wallHeight + toggleBBoxHalfHeight + 0.025
        
        @MainActor func makePrismToggle() -> ModelEntity {
            let prism = ModelEntity()
            let yMat = SimpleMaterial(color: .yellow, isMetallic: false)
            let rMat = SimpleMaterial(color: .red, isMetallic: false)
            let bMat = SimpleMaterial(color: .blue, isMetallic: false)
            let supportMat = SimpleMaterial(color: .black, isMetallic: true)
            let s = toggleSide
            let L = toggleLength
            
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
        
        // N/S share the same Y-rotation, and E/W share the same Y-rotation
        // (translated, not mirrored). One side ends up red-inward and the opposite side red-outward.
        let toggleConfigs: [(SIMD3<Float>, Float)] = [
            ([0, toggleCenterY,  halfField],  .pi / 2),   // N wall (red faces toward field)
            ([0, toggleCenterY, -halfField],  .pi / 2),   // S wall (same rotation as N)
            ([ halfField, toggleCenterY, 0],  0),         // E wall
            ([-halfField, toggleCenterY, 0],  0),         // W wall (same rotation as E)
        ]
        for (pos, yRot) in toggleConfigs {
            let t = makePrismToggle()
            t.position = pos
            t.orientation = simd_quatf(angle: yRot, axis: [0, 1, 0])
            fieldContainer.addChild(t)
        }
        
        // --- MATCH LOAD CHUTES (hollow 3D structure + U-shape tape on floor) ---
        // Tape U: 1 tile along the wall × half-tile into the field
        let tileSize: Float = fieldSize / 6
        let tapeIntoField: Float = tileSize / 2       // ~0.304m
        let tapeWidth: Float = 0.035
        // Chute body — much smaller, fits inside the U
        let chuteW: Float = 0.09   // along the wall direction
        let chuteD: Float = 0.09   // perpendicular into field
        let chuteH: Float = 0.40
        let chuteT: Float = 0.005   // wall thickness
        let chuteBodyMat = SimpleMaterial(color: .lightGray, isMetallic: false)
        
        // Build a chute as if it sits on the W wall (opening toward +X / field).
        // For the E wall, rotate the whole assembly 180° around Y.
        @MainActor func makeChute(tapeColor: UIColor) -> Entity {
            let chute = Entity()
            let topMat = SimpleMaterial(color: tapeColor, isMetallic: false)
            // Chute body is shifted toward the back (near the perimeter wall side)
            let bodyOffsetX: Float = -tapeIntoField / 2 + tapeWidth + 0.012 + chuteD / 2
            
            // Handle that lies on top of the perimeter wall (a person grabs this to lift the loader)
            let handle = ModelEntity(
                mesh: .generateBox(size: [chuteT, chuteT, chuteW - 0.02]),
                materials: [chuteBodyMat]
            )
            handle.position = [bodyOffsetX - chuteD / 2 + chuteT, chuteH + chuteT, 0]
            chute.addChild(handle)
            
            // Half wall on the field-facing side
            let front = ModelEntity(
                mesh: .generateBox(size: [chuteT, chuteH * 0.7, chuteW]),
                materials: [chuteBodyMat]
            )
            front.position = [bodyOffsetX + chuteD / 2 - chuteT / 2, chuteH * 0.65, 0]
            chute.addChild(front)
            
            // Two side walls
            for sideZ in [-(chuteW / 2 - chuteT / 2), (chuteW / 2 - chuteT / 2)] {
                let side = ModelEntity(
                    mesh: .generateBox(size: [chuteD, chuteH, chuteT]),
                    materials: [chuteBodyMat]
                )
                side.position = [bodyOffsetX, chuteH / 2, sideZ]
                chute.addChild(side)
            }
            
            // Colored U-shaped top: 2 parallel strips along X + 1 connecting strip on the field-interior side
            let topStripT: Float = 0.01
            let topY: Float = chuteH + topStripT / 2
            for stripZ: Float in [-(chuteW / 2 - topStripT / 2), (chuteW / 2 - topStripT / 2)] {
                let strip = ModelEntity(
                    mesh: .generateBox(size: [chuteD, topStripT, topStripT]),
                    materials: [topMat]
                )
                strip.position = [bodyOffsetX, topY, stripZ]
                chute.addChild(strip)
            }
            let connect = ModelEntity(
                mesh: .generateBox(size: [topStripT, topStripT, chuteW]),
                materials: [topMat]
            )
            connect.position = [bodyOffsetX + chuteD / 2 - topStripT / 2, topY, 0]
            chute.addChild(connect)
            
            return chute
        }
        
        // 4 chutes: 2 red (W wall, NW + SW), 2 blue (E wall, NE + SE)
        let chuteWallInset: Float = tapeIntoField / 2 - 0.02
        let chuteCornerInset: Float = 0.5 * tileSize    // chute sits at the end of the L tape's long leg
        
        struct ChuteSpec { let pos: SIMD3<Float>; let yRot: Float; let color: UIColor }
        
        // 1. Break up the complex math into separate, simple sub-expressions
        let nwPos = SIMD3<Float>(-halfField + chuteWallInset, 0,  halfField - chuteCornerInset)
        let swPos = SIMD3<Float>(-halfField + chuteWallInset, 0, -halfField + chuteCornerInset)
        let nePos = SIMD3<Float>( halfField - chuteWallInset, 0,  halfField - chuteCornerInset)
        let sePos = SIMD3<Float>( halfField - chuteWallInset, 0, -halfField + chuteCornerInset)
        
        // 2. Feed the pre-calculated positions into the array literal
        let chuteSpecs: [ChuteSpec] = [
            ChuteSpec(pos: nwPos, yRot: 0,     color: .systemRed),  // NW
            ChuteSpec(pos: swPos, yRot: 0,     color: .systemRed),  // SW
            ChuteSpec(pos: nePos, yRot: .pi,   color: .systemBlue), // NE
            ChuteSpec(pos: sePos, yRot: .pi,   color: .systemBlue)  // SE
        ]
        
        for spec in chuteSpecs {
            let chute = makeChute(tapeColor: spec.color)
            chute.position = spec.pos
            chute.orientation = simd_quatf(angle: spec.yRot, axis: [0, 1, 0])
            fieldContainer.addChild(chute)
        }
        
        // L-shape floor tape at each match-load corner
        // - "horizontal" leg (parallel to N/S wall) is 1/2 tile, runs from the corner toward the L vertex
        // - "vertical" leg (parallel to W/E wall) is 1 tile, runs from the L vertex deeper into the field
        let lTapeSpecs: [(SIMD3<Float>, Float, Float, UIColor)] = [
            // (field corner, xInsideSign, zInsideSign, color)
            ([-halfField, 0,  halfField],  1, -1, .systemRed),    // NW
            ([-halfField, 0, -halfField],  1,  1, .systemRed),    // SW
            ([ halfField, 0,  halfField], -1, -1, .systemBlue),   // NE
            ([ halfField, 0, -halfField], -1,  1, .systemBlue),   // SE
        ]
        for (corner, xInside, zInside, color) in lTapeSpecs {
            let mat = SimpleMaterial(color: color, isMetallic: false)
            let lVertexX = corner.x + xInside * 0.5 * tileSize
            
            // Horizontal leg (along X, length = 0.5 tile)
            let horiz = ModelEntity(
                mesh: .generatePlane(width: 0.5 * tileSize, depth: tapeWidth),
                materials: [mat]
            )
            horiz.position = [corner.x + xInside * 0.25 * tileSize, 0.003, corner.z * tileSize * 1.1]
            fieldContainer.addChild(horiz)
            
            // Vertical leg (along Z, length = 1 tile)
            let vert = ModelEntity(
                mesh: .generatePlane(width: tapeWidth, depth: tileSize * 1.045),
                materials: [mat]
            )
            vert.position = [lVertexX, 0.003, corner.z + zInside * 0.5 * tileSize]
            fieldContainer.addChild(vert)
        }
        
        //<----------------------- Game elements ------------------------->

        // Shared physics material for all pins — a bit of friction + small bounce.
        let pinMaterial = PhysicsMaterialResource.generate(friction: 0.6, restitution: 0.1)
        

        // Bundle holding everything we need to respawn a pin if it falls off the field.
        struct GamePin {
            let entity: Entity
            let spawn: SIMD3<Float>
            let shape: ShapeResource
        }
        
        if let masterScene = try? await Entity(named: "Scene", in: roboticsSimulationAssetsBundle) {
            // Add / remove / re-color pins here. Format: (position, top color, bottom color).
            let pinPlacements: [(SIMD3<Float>, PinHalfColor, PinHalfColor)] = [
                (SIMD3<Float>( 0.5, 0.6,  0.5), .red,    .blue),
                (SIMD3<Float>(-0.5, 0.6,  0.5), .yellow, .yellow),
                (SIMD3<Float>( 0.5, 0.6, -0.5), .red,    .yellow),
                (SIMD3<Float>(-0.5, 0.6, -0.5), .blue,   .yellow),
            ]
            
            var gamePins: [GamePin] = []
            for (position, top, bottom) in pinPlacements {
                if let p = await makePin(top: top, bottom: bottom, at: position, scene: masterScene) {
                    fieldContainer.addChild(p.entity)
                    gamePins.append(p)
                }
            }
            
            // One subscription respawns any pin that's fallen off the field.
            let respawnPins = gamePins
            _ = content.subscribe(to: SceneEvents.Update.self) { _ in
                for spec in respawnPins {
                    guard spec.entity.position(relativeTo: nil).y < Self.respawnThreshold else { continue }
                    spec.entity.components.remove(PhysicsBodyComponent.self)
                    spec.entity.components.remove(CollisionComponent.self)
                    spec.entity.components.remove(PhysicsMotionComponent.self)
                    
                    spec.entity.position = spec.spawn
                    spec.entity.orientation = simd_quatf(angle: 0, axis: [0, 1, 0])
                    
                    var body = PhysicsBodyComponent(shapes: [spec.shape], mass: 0.1, material: pinMaterial, mode: .dynamic)
                    body.linearDamping = 0.3
                    body.angularDamping = 0.6
                    spec.entity.components.set(CollisionComponent(shapes: [spec.shape]))
                    spec.entity.components.set(body)
                    spec.entity.components.set(PhysicsMotionComponent())
                }
            }
            
            content.add(fieldContainer)
            content.cameraTarget = floorEntity
        }
        
        // Build a fresh, physics-ready pin instance. Asset filename is derived from
        // the two half-colors: e.g. (top: .red, bottom: .blue) → "RedBluePin.usdz".
        @MainActor
        func makePin(top: PinHalfColor, bottom: PinHalfColor, at position: SIMD3<Float>, scene: Entity) async -> GamePin? {
            let assetName = "\(top.rawValue)\(bottom.rawValue)Pin"
            
            if let pin = scene.findEntity(named: assetName) {
                pin.scale *= 0.5
                pin.position = position
                
                let bounds = pin.visualBounds(relativeTo: pin)
                let shape = ShapeResource.generateBox(size: bounds.extents)
                    .offsetBy(translation: bounds.center)
                var body = PhysicsBodyComponent(shapes: [shape], mass: 0.1, material: pinMaterial, mode: .dynamic)
                body.linearDamping = 0.3
                body.angularDamping = 0.6
                pin.components.set(CollisionComponent(shapes: [shape]))
                pin.components.set(body)
                pin.components.set(PhysicsMotionComponent())
                
                return GamePin(entity: pin, spawn: position, shape: shape)
            }else{
                print("[RoboSim] Missing pin asset: \(assetName).usdz")
                return nil
            }
        }
    }
    #endif
}
