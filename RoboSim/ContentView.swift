import SwiftUI
import RealityKit
import Field_Model

struct ContentView: View {
    @State private var cameraMode: CameraMode = .thirdPerson
    @State private var leftStickOffset: CGSize = .zero
    @State private var rightStickOffset: CGSize = .zero
    @State private var driveInput = DriveInput()
    @State private var armUp: Bool = false
    @State private var armDown: Bool = false
    @State private var intakeIn: Bool = false
    @State private var intakeOut: Bool = false
    @State private var physicsDebug: Bool = false

    var body: some View {
        ZStack {
            realityLayer
            hudLayer
        }
        .onChange(of: leftStickOffset)  { _, v in updateForward(v) }
        .onChange(of: rightStickOffset) { _, v in updateTurn(v) }
        .onChange(of: armUp)     { _, v in driveInput.armUp = v }
        .onChange(of: armDown)   { _, v in driveInput.armDown = v }
        .onChange(of: intakeIn)  { _, v in driveInput.intakeIn = v }
        .onChange(of: intakeOut) { _, v in driveInput.intakeOut = v }
    }

    private var realityLayer: some View {
        RealityView { content in
            await makeScene(content: &content)
        } update: { content in
            updateCameraMode(content: content)
            updatePhysicsDebug(content: content)
        }
        // `.pan` slides the camera laterally without rotating around the
        // target. System pinch-to-zoom still works alongside it. Swap to
        // `.orbit` for rotation, or `.dolly` for forward/back only.
        .realityViewCameraControls(cameraMode == .thirdPerson ? .orbit : .none)
        .edgesIgnoringSafeArea(.all)
    }

    private var hudLayer: some View {
        HUDOverlay(leftStickOffset: $leftStickOffset,
                   rightStickOffset: $rightStickOffset,
                   cameraMode: $cameraMode,
                   armUp: $armUp,
                   armDown: $armDown,
                   intakeIn: $intakeIn,
                   intakeOut: $intakeOut,
                   physicsDebug: $physicsDebug,
                   onReset: { driveInput.resetRequested = true })
    }

    private func updateForward(_ newValue: CGSize) {
        let raw = Float(-newValue.height / SimulationConstants.joystickRadius)
        driveInput.forward = max(-1, min(1, raw))
    }

    private func updateTurn(_ newValue: CGSize) {
        let raw = Float(newValue.width / SimulationConstants.joystickRadius)
        driveInput.turn = max(-1, min(1, raw))
    }

    // Anchor the loaded field root so the debug-overlay updater can find it
    // without re-traversing all of content.entities each frame.
    private static let fieldRootName = "MatchSimulatorRoot"

    @State private var debugOverlay: FieldRuntime.PhysicsDebugOverlay?

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

        let fieldRoot = await setupRoboticsField(content: &content)

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

        // Wire post-load field processing (pin staticize, tape de-collide)
        // and the matchloader lift animation that the drive loop will tick.
        var lifter: FieldRuntime.MatchLoaderLifter? = nil
        if let fieldRoot {
            FieldRuntime.process(scene: fieldRoot)
            lifter = FieldRuntime.MatchLoaderLifter(root: fieldRoot)
            debugOverlay = FieldRuntime.PhysicsDebugOverlay(root: fieldRoot)
        }

        RobotBuilder.attachDriveLoop(content: content,
                                     robotEntity: robotEntity,
                                     cameraEntity: cameraEntity,
                                     input: driveInput,
                                     surfaceMaterial: surfaceMaterial,
                                     fieldRoot: fieldRoot,
                                     matchLoaderLifter: lifter)
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

    @MainActor
    private func updatePhysicsDebug(content: RealityViewCameraContent) {
        guard let overlay = debugOverlay else { return }
        if physicsDebug {
            overlay.show()
        } else {
            overlay.hide()
        }
    }

    #if os(iOS) || os(macOS)
    @MainActor
    private func setupRoboticsField(content: inout RealityViewCameraContent) async -> Entity? {
        // The Match_Simulator package's Scene.usda is the whole world:
        // Boundaries (floor + walls + alliance tapes) and Field_Master
        // (visual field plus baked physics for pins, rollers, matchloaders).
        // After loading we hand the root to FieldRuntime.process for
        // pin/tape cleanup.
        guard let masterScene = try? await Entity(named: "Scene", in: field_ModelBundle) else {
            return nil
        }
        masterScene.name = Self.fieldRootName
        content.add(masterScene)
        return masterScene
    }
    #endif
}
