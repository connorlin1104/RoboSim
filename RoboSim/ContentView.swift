import SwiftUI
import RealityKit
import RoboticsSimulationAssets

struct ContentView: View {
    @State private var cameraMode: CameraMode = .thirdPerson
    @State private var leftStickOffset: CGSize = .zero
    @State private var rightStickOffset: CGSize = .zero
    @State private var driveInput = DriveInput()
    @State private var matchLoad = MatchLoadController()

    var body: some View {
        ZStack {
            RealityView { content in
                await makeScene(content: &content)
            } update: { content in
                updateCameraMode(content: content)
            }
            // `.pan` slides the camera laterally without rotating around the
            // target. System pinch-to-zoom still works alongside it. Swap to
            // `.orbit` for rotation, or `.dolly` for forward/back only.
            .realityViewCameraControls(cameraMode == .thirdPerson ? .orbit : .none)
            .edgesIgnoringSafeArea(.all)

            HUDOverlay(leftStickOffset: $leftStickOffset,
                       rightStickOffset: $rightStickOffset,
                       cameraMode: $cameraMode,
                       matchLoad: matchLoad)
        }
        .onChange(of: leftStickOffset) { _, newValue in
            driveInput.forward = max(-1, min(1, Float(-newValue.height / SimulationConstants.joystickRadius)))
        }
        .onChange(of: rightStickOffset) { _, newValue in
            driveInput.turn = max(-1, min(1, Float(newValue.width / SimulationConstants.joystickRadius)))
        }
    }

    // RealityView's make closure body. Pulled out as a method because
    // having all of this inline made the Swift type-checker time out.
    @MainActor
    private func makeScene(content: inout RealityViewCameraContent) async {
        content.camera = .virtual

        FollowCameraSystem.registerSystem()
        FollowCameraComponent.registerComponent()

        // Shared surface material — gives floor/walls grip so loose game
        // pieces settle. The robot ignores friction while upright because
        // its velocity is set directly each frame; once tipped it falls
        // back on physics + this friction to stop sliding.
        let surfaceMaterial = PhysicsMaterialResource.generate(friction: 0.5, restitution: 0)

        await setupRoboticsField(content: &content, surfaceMaterial: surfaceMaterial)

        // --- ROBOT ---
        let robotEntity = RobotBuilder.build(surfaceMaterial: surfaceMaterial)
        content.add(robotEntity)

        // --- CAMERA ---
        let cameraEntity = Entity()
        cameraEntity.name = "MainCamera"
        let camTarget: SIMD3<Float> = .zero
        cameraEntity.look(at: camTarget,
                          from: SimulationConstants.thirdPersonPosition,
                          relativeTo: nil)
        cameraEntity.components.set(PerspectiveCameraComponent())
        content.add(cameraEntity)

        // --- LIGHTING ---
        let light = DirectionalLight()
        light.light.intensity = 5000
        let lightTarget: SIMD3<Float> = [0, 0, 0]
        let lightFrom: SIMD3<Float> = [2, 5, 2]
        light.look(at: lightTarget, from: lightFrom, relativeTo: nil)
        content.add(light)

        RobotBuilder.attachDriveLoop(content: content,
                                     robotEntity: robotEntity,
                                     cameraEntity: cameraEntity,
                                     input: driveInput,
                                     surfaceMaterial: surfaceMaterial)
    }

    // Reacts to SwiftUI camera-mode flips by attaching/detaching the
    // FollowCameraComponent. Pulled out of the RealityView update closure
    // because the inlined version was tripping the Swift type-checker.
    @MainActor
    private func updateCameraMode(content: RealityViewCameraContent) {
        let mainCamera = content.entities.first(where: { ($0 as Entity).name == "MainCamera" })
        guard let camera = mainCamera else { return }
        let hasFollowComponent = camera.components[FollowCameraComponent.self] != nil

        switch cameraMode {
        case .thirdPerson:
            if hasFollowComponent {
                camera.components.remove(FollowCameraComponent.self)
                let target: SIMD3<Float> = .zero
                camera.look(at: target,
                            from: SimulationConstants.thirdPersonPosition,
                            relativeTo: nil)
            }
        case .firstPerson:
            if !hasFollowComponent {
                camera.components.set(FollowCameraComponent())
            }
        }
    }

    #if os(iOS) || os(macOS)
    @MainActor
    private func setupRoboticsField(content: inout RealityViewCameraContent,
                                    surfaceMaterial: PhysicsMaterialResource) async {
        let fieldContainer = Entity()

        // --- Load the master Reality Composer Pro scene first so the
        // --- matchloader assets are available to LoadingZones ------------
        // Gated by `useLegacyRCPScene` so we don't even attempt the load
        // (and don't print "Missing X asset" warnings downstream) while
        // the asset library is being migrated.
        let masterScene: Entity? = SimulationConstants.useLegacyRCPScene
            ? (try? await Entity(named: "Scene", in: roboticsSimulationAssetsBundle))
            : nil

        // --- Static field structure --------------------------------------
        FieldStructure.build(into: fieldContainer, surfaceMaterial: surfaceMaterial)
        Goals.build(into: fieldContainer, surfaceMaterial: surfaceMaterial)
        Toggles.build(into: fieldContainer, surfaceMaterial: surfaceMaterial)
        let platform = LoadingZones.build(into: fieldContainer,
                                          surfaceMaterial: surfaceMaterial,
                                          masterScene: masterScene)

        // --- Pregame game piece placements -------------------------------
        let placements = Placements.compute(platform: platform)

        guard let masterScene = masterScene else {
            content.add(fieldContainer)
            return
        }

        var gamePins: [GamePin] = []
        for placement in placements.pins {
            if let p = PinFactory.makePin(top: placement.top,
                                          bottom: placement.bottom,
                                          at: placement.position,
                                          stance: placement.stance,
                                          yawDegrees: placement.yawDegrees,
                                          isStatic: false,
                                          scene: masterScene) {
                fieldContainer.addChild(p.entity)
                gamePins.append(p)
            }
        }

        // Spawn cups.
        for placement in placements.cups {
            if let cup = CupFactory.makeCup(at: placement.position,
                                            upsideDown: placement.upsideDown,
                                            isStatic: false,
                                            surfaceMaterial: surfaceMaterial,
                                            scene: masterScene) {
                fieldContainer.addChild(cup)
            }
        }

        MatchLoadSpawner.attachUpdateLoop(content: content,
                                          fieldContainer: fieldContainer,
                                          masterScene: masterScene,
                                          surfaceMaterial: surfaceMaterial,
                                          respawnPins: gamePins,
                                          matchLoad: matchLoad)

        content.add(fieldContainer)
    }
    #endif
}
