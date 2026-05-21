import RealityKit
import SwiftUI

// Spawns "match-loaded" stacks (cup + pin) into the field at one of the
// four corner chutes, picked by alliance (red→west, blue→east) and the
// robot's Z position (north/south half of the field).
//
// Also owns the per-frame scene subscription that:
//   • respawns any pregame pin that's fallen off the field
//   • drains the HUD button queue and triggers a spawn per press
enum MatchLoadSpawner {

    @MainActor
    static func attachUpdateLoop(content: RealityViewCameraContent,
                                 fieldContainer: Entity,
                                 masterScene: Entity,
                                 surfaceMaterial: PhysicsMaterialResource,
                                 respawnPins: [GamePin],
                                 matchLoad: MatchLoadController) {
        _ = content.subscribe(to: SceneEvents.Update.self) { event in
            // 1) Respawn pregame pins that fell off the field.
            for spec in respawnPins {
                guard spec.entity.position(relativeTo: nil).y < SimulationConstants.respawnThreshold else { continue }
                spec.entity.components.remove(PhysicsBodyComponent.self)
                spec.entity.components.remove(CollisionComponent.self)
                spec.entity.components.remove(PhysicsMotionComponent.self)

                spec.entity.position = spec.spawn
                spec.entity.orientation = simd_quatf(angle: 0, axis: [0, 1, 0])

                var body = PhysicsBodyComponent(shapes: [spec.shape], mass: 0.1, material: PinFactory.physicsMaterial, mode: .dynamic)
                body.linearDamping = 0.2
                body.angularDamping = 0.15
                spec.entity.components.set(CollisionComponent(shapes: [spec.shape]))
                spec.entity.components.set(body)
                spec.entity.components.set(PhysicsMotionComponent())
            }

            // 2) Drain HUD match-load presses. Sample the robot's Z once
            // per frame so each spawn picks the north/south chute on the
            // alliance's side based on which half the robot is in.
            let robot = event.scene.findEntity(named: "VEX_Robot")
            let robotZ: Float = robot?.position(relativeTo: nil).z ?? 0
            while matchLoad.pendingRed > 0 {
                matchLoad.pendingRed -= 1
                spawnMatchLoadedPin(alliance: .red, robotZ: robotZ,
                                    fieldContainer: fieldContainer,
                                    masterScene: masterScene,
                                    surfaceMaterial: surfaceMaterial)
            }
            while matchLoad.pendingBlue > 0 {
                matchLoad.pendingBlue -= 1
                spawnMatchLoadedPin(alliance: .blue, robotZ: robotZ,
                                    fieldContainer: fieldContainer,
                                    masterScene: masterScene,
                                    surfaceMaterial: surfaceMaterial)
            }
        }
    }

    // Spawns a "match-loaded" stack inside the field: one upside-down cup
    // followed immediately by an alliance/yellow pin dropped just above
    // it. Mirrors the diamond-corner / double-line in-field stacks: cup
    // and pin spawn together at the same XZ, with the pin starting just
    // above the cup so it falls into the cup's well as the cup settles.
    //
    // The drop location picks one of the FOUR field-corner chutes based on:
    //   • alliance — RED always drops on the west (X < 0) side, BLUE on
    //                the east (X > 0) side.
    //   • robotZ   — picks the NORTH or SOUTH chute on the alliance side.
    //                Z ≥ 0 → north chute; Z < 0 → south.
    @MainActor
    static func spawnMatchLoadedPin(alliance: PinHalfColor,
                                    robotZ: Float,
                                    fieldContainer: Entity,
                                    masterScene: Entity,
                                    surfaceMaterial: PhysicsMaterialResource) {
        let halfField = SimulationConstants.halfField
        let matchLoadInsetX:   Float  = 0.45
        let matchLoadInsetZ:   Float  = 0.45
        // Match the in-field stack drop heights so behaviour is identical
        // to the diamond / double-line stacks the user verified working.
        let cupDropY:          Float  = 0.1     // == InFieldPlacements.inFieldCupY
        let pinDropY:          Float  = 0.21    // == InFieldPlacements.inFieldPinAboveCup

        // X side is set by the alliance — red on west, blue on east.
        let dropX: Float = alliance == .red
        ? -halfField + matchLoadInsetX / 2
        :  halfField - matchLoadInsetX / 2
        // Z side is set by which half of the field the robot is on.
        let dropZ: Float = robotZ >= 0
        ?  halfField - matchLoadInsetZ / 2 - 0.08
        : -halfField + matchLoadInsetZ / 2 + 0.08

        // 1) Drop the cup upside-down so the hollow well faces up — the
        //    same orientation the diamond/double-line stacks use.
        if let cup = CupFactory.makeCup(at: SIMD3<Float>(dropX, cupDropY, dropZ),
                                        upsideDown: true,
                                        surfaceMaterial: surfaceMaterial,
                                        scene: masterScene) {
            fieldContainer.addChild(cup)
        }
        // 2) Drop the pin in the same frame at the same XZ. (Yellow/yellow
        //    pins are decor-only — never spawned here.) Not appended to
        //    `gamePins` — match-loaded stacks aren't tracked for fall-off-
        //    the-field respawn.
        if let p = PinFactory.makePin(top: alliance, bottom: .yellow,
                                      at: SIMD3<Float>(dropX, pinDropY, dropZ),
                                      stance: .vertical, scene: masterScene) {
            fieldContainer.addChild(p.entity)
        }
    }
}
