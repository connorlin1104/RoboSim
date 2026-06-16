import SwiftUI
import RealityKit
import Field_Model

struct ContentView: View {
    @State private var cameraMode: CameraMode = .thirdPerson
    @State private var leftStickOffset: CGSize = .zero
    @State private var rightStickOffset: CGSize = .zero
    @State private var driveInput = DriveInput()

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
                       cameraMode: $cameraMode)
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

        // Shared surface material — gives the robot grip once it tips
        // and falls onto the floor. While upright the robot's velocity is
        // set directly each frame so friction doesn't matter.
        let surfaceMaterial = PhysicsMaterialResource.generate(friction: 0.5, restitution: 0)

        await setupRoboticsField(content: &content)

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
    private func setupRoboticsField(content: inout RealityViewCameraContent) async {
        // The Match_Simulator package's Scene.usda is the whole world:
        // Floor_Physics + N/S/E/W Wall_Physics give the static perimeter,
        // and Field_Master/OverRideFieldCleaned is the visual art plus
        // baked-in pin physics. Cup and goal physics are still TODO
        // (hollow shapes are harder to author by hand).
        guard let masterScene = try? await Entity(named: "Scene", in: field_ModelBundle) else {
            return
        }
        content.add(masterScene)
    }
    #endif
}
