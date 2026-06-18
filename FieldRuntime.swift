import RealityKit
import UIKit

// Runtime cleanup + animation for the field. Everything in here runs after
// the Reality Composer Pro Scene loads so we can override anything the .usda
// got wrong (pin dynamics, tape colliders, etc.) and wire up the matchloader
// lift animation.
enum FieldRuntime {

    // MARK: Post-load processing

    // Walk the loaded scene and fix up problem entities:
    //   1. Every "Pins_*" gets forced to static so they can't drop through
    //      the floor regardless of what the .usda said.
    //   2. The four alliance tape lines get their CollisionComponent stripped
    //      so the robot drives over them freely — we detect "robot on tape"
    //      via position checks each frame, not collision events.
    @MainActor
    static func process(scene root: Entity) {
        forceStaticPins(under: root)
        stripTapeColliders(under: root)
        installPinLayout(PinLayout.pins, under: root)
    }

    // Re-apply the static pin layout from PinLayout.pins. Called by the
    // Reset button — clears any current PinSpecLayout clones and respawns
    // them at their authored positions.
    @MainActor
    static func resetPinLayout(under root: Entity) {
        installPinLayout(PinLayout.pins, under: root)
    }

    // Clone each pin spec from its matching RCP prefab (RedBluePin etc.)
    // and stash the clones under a `PinSpecLayout` group. The originals
    // stay in the tree as templates but are disabled so they don't show
    // wherever you placed them in RCP.
    @MainActor
    static func installPinLayout(_ specs: [PinSpec], under root: Entity) {
        guard !specs.isEmpty else { return }

        var templates: [PinVariant: Entity] = [:]
        for variant in [PinVariant.redBlue, .yellowYellow, .redYellow, .blueYellow] {
            if let t = root.findEntity(named: variant.rawValue) {
                templates[variant] = t
            }
        }
        guard !templates.isEmpty else { return }

        let group: Entity
        if let existing = root.findEntity(named: "PinSpecLayout") {
            group = existing
            for child in Array(group.children) { child.removeFromParent() }
        } else {
            group = Entity()
            group.name = "PinSpecLayout"
            root.addChild(group)
        }

        for spec in specs {
            guard let template = templates[spec.variant] else { continue }
            let clone = template.clone(recursive: true)
            clone.name = "Pin_\(spec.variant.rawValue)_\(group.children.count)"
            clone.isEnabled = true
            group.addChild(clone)
            // Bump Y up by a small margin so pins start *just above* the
            // floor instead of clipping into it — initial overlap is the
            // usual cause of explosive impulses on layout-spawn.
            var pos = spec.position
            pos.y += 0.02
            clone.setPosition(pos, relativeTo: nil)
            clone.setOrientation(spec.orientation.quaternion, relativeTo: nil)
            // Heavy damping on the cloned PhysicsBody so packed neighbors
            // settle instead of flinging each other. The template's mass /
            // mode / material are preserved; only damping is overridden.
            if var body = clone.components[PhysicsBodyComponent.self] {
                body.angularDamping = 4.0
                body.linearDamping  = 1.0
                clone.components.set(body)
            }
        }

        for template in templates.values {
            template.isEnabled = false
        }
    }

    @MainActor
    private static func forceStaticPins(under root: Entity) {
        // The original .usda pin colliders have per-pin `pose.position`
        // offsets baked from the source CAD that don't match the visible
        // mesh, so any motion type (static / kinematic / dynamic) leaves
        // invisible obstacles scattered around the field. We strip the
        // physics and collision entirely; gameplay pins are added back via
        // hand-authored `cadPinModel` duplicates under `Pins_Manual` in
        // Reality Composer Pro.
        walk(root) { entity in
            guard entity.name.hasPrefix("Pins_") else { return }
            entity.components.remove(CollisionComponent.self)
            entity.components.remove(PhysicsBodyComponent.self)
        }
    }

    @MainActor
    private static func stripTapeColliders(under root: Entity) {
        for name in ["Red_Bottom", "Red_Top", "Blue_Bottom", "Blue_Top"] {
            guard let line = root.findEntity(named: name) else { continue }
            line.components.remove(CollisionComponent.self)
            line.components.remove(PhysicsBodyComponent.self)
        }
    }

    // MARK: Matchloader lift animation

    // Resolved at scene-load time once so the per-frame update isn't doing
    // name lookups. Each matchloader pair (the two _001 and unsuffixed
    // entities on each side) lift together when the robot is on a tape line
    // of the matching alliance color.
    @MainActor
    final class MatchLoaderLifter {
        struct TapeAABB {
            let minXZ: SIMD2<Float>
            let maxXZ: SIMD2<Float>
            let centerXZ: SIMD2<Float>
        }

        // Each loader is paired with the single nearest tape line of its
        // alliance color. Robot on that line → that loader (and only that
        // loader) lifts AND a fresh pin is spawned just above it after a
        // short delay (so the moving loader doesn't fling the pin upward).
        final class Pair {
            let loader: Entity
            let restWorldPos: SIMD3<Float>     // entity origin → drives lift animation
            let visualCenter: SIMD3<Float>     // world-space mesh center → spawn anchor
            let loaderTopY: Float              // world-space top of loader at rest
            let line: TapeAABB
            let spawnVariant: PinVariant
            var phase: Float = 0
            var hasSpawnedThisVisit: Bool = false
            var pendingSpawnDelay: Float? = nil    // seconds until the queued spawn fires
            init(loader: Entity,
                 restWorldPos: SIMD3<Float>,
                 visualCenter: SIMD3<Float>,
                 loaderTopY: Float,
                 line: TapeAABB,
                 spawnVariant: PinVariant) {
                self.loader = loader
                self.restWorldPos = restWorldPos
                self.visualCenter = visualCenter
                self.loaderTopY = loaderTopY
                self.line = line
                self.spawnVariant = spawnVariant
            }
        }

        private var pairs: [Pair] = []
        private var pinTemplates: [PinVariant: Entity] = [:]
        private weak var spawnGroup: Entity?
        // Cached so we don't recreate it per spawned pin.
        private let spawnedPinMaterial: PhysicsMaterialResource =
            .generate(staticFriction: 0.8, dynamicFriction: 0.7, restitution: 0.0)

        @MainActor
        init?(root: Entity) {
            let inflate = SimulationConstants.tapeDetectInflateXZ
            func tapeAABB(_ named: String) -> TapeAABB? {
                guard let e = root.findEntity(named: named) else { return nil }
                let b = e.visualBounds(relativeTo: nil)
                let center = (b.min + b.max) * 0.5
                return TapeAABB(
                    minXZ: SIMD2(b.min.x - inflate, b.min.z - inflate),
                    maxXZ: SIMD2(b.max.x + inflate, b.max.z + inflate),
                    centerXZ: SIMD2(center.x, center.z)
                )
            }

            let blueLines = ["Blue_Top", "Blue_Bottom"].compactMap(tapeAABB)
            let redLines  = ["Red_Top",  "Red_Bottom"].compactMap(tapeAABB)
            guard !blueLines.isEmpty || !redLines.isEmpty else { return nil }

            // We need four things per loader:
            //   - entity origin in world coords (for the lift animation —
            //     setPosition writes the origin)
            //   - visual bounds center in world coords (for spawn anchor X/Z —
            //     loader's mesh sits at an offset from its origin, so using
            //     the origin for spawns lands pins in the middle of the field)
            //   - visual bounds top Y (so spawned pins clear the *actual* top
            //     of the loader instead of getting punched through it)
            //   - origin XZ pair the assignment optimizer can sort by
            struct Resolved {
                let entity: Entity
                let originXZ: SIMD2<Float>
                let originWorld: SIMD3<Float>
                let visualCenter: SIMD3<Float>
                let loaderTopY: Float
            }

            func pair(loaderNames: [String], lines: [TapeAABB], spawnVariant: PinVariant) -> [Pair] {
                let resolved: [Resolved] = loaderNames.compactMap { name in
                    guard let e = root.findEntity(named: name) else { return nil }
                    let p = e.position(relativeTo: nil)
                    let bounds = e.visualBounds(relativeTo: nil)
                    let center = (bounds.min + bounds.max) * 0.5
                    return Resolved(entity: e,
                                    originXZ: SIMD2(p.x, p.z),
                                    originWorld: p,
                                    visualCenter: center,
                                    loaderTopY: bounds.max.y)
                }
                guard !resolved.isEmpty, !lines.isEmpty else { return [] }

                func sqDist(_ a: SIMD2<Float>, _ b: SIMD2<Float>) -> Float {
                    simd_length_squared(a - b)
                }

                // 2-loader / 2-line assignment: try both permutations and
                // pick the lower total. Guarantees each line is paired with
                // at most one loader.
                let mapping: [Int]
                if resolved.count == 2 && lines.count == 2 {
                    // Pair by visual center XZ — that's where the loader
                    // actually appears, not where its hidden entity origin
                    // lives.
                    let v0 = SIMD2(resolved[0].visualCenter.x, resolved[0].visualCenter.z)
                    let v1 = SIMD2(resolved[1].visualCenter.x, resolved[1].visualCenter.z)
                    let direct  = sqDist(lines[0].centerXZ, v0)
                                + sqDist(lines[1].centerXZ, v1)
                    let swapped = sqDist(lines[1].centerXZ, v0)
                                + sqDist(lines[0].centerXZ, v1)
                    mapping = direct <= swapped ? [0, 1] : [1, 0]
                } else {
                    mapping = resolved.map { r in
                        let v = SIMD2(r.visualCenter.x, r.visualCenter.z)
                        return (0..<lines.count).min(by: {
                            sqDist(lines[$0].centerXZ, v) <
                            sqDist(lines[$1].centerXZ, v)
                        })!
                    }
                }

                var out: [Pair] = []
                for (i, r) in resolved.enumerated() {
                    out.append(Pair(loader: r.entity,
                                    restWorldPos: r.originWorld,
                                    visualCenter: r.visualCenter,
                                    loaderTopY: r.loaderTopY,
                                    line: lines[mapping[i]],
                                    spawnVariant: spawnVariant))
                }
                return out
            }

            self.pairs =
                pair(loaderNames: ["BlueMatchLoader", "BlueMatchLoader_001"],
                     lines: blueLines, spawnVariant: .blueYellow) +
                pair(loaderNames: ["RedMatchLoader",  "RedMatchLoader_001"],
                     lines: redLines,  spawnVariant: .redYellow)

            guard !pairs.isEmpty else { return nil }

            // Cache pin prefab templates so we can clone them at spawn time
            // without re-walking the scene. Templates may be disabled by
            // PinLayout — `findEntity` still locates them.
            for variant in [PinVariant.redBlue, .yellowYellow, .redYellow, .blueYellow] {
                if let t = root.findEntity(named: variant.rawValue) {
                    pinTemplates[variant] = t
                }
            }

            let group = Entity()
            group.name = "SpawnedMatchLoaderPins"
            root.addChild(group)
            self.spawnGroup = group
        }

        @MainActor
        func tick(dt: Float, robotEntity: Entity) {
            // AABB-vs-AABB: trigger if any part of the robot's visual
            // bounding box overlaps the tape line, not just its origin.
            let rb = robotEntity.visualBounds(relativeTo: nil)
            let rMinX = rb.min.x, rMaxX = rb.max.x
            let rMinZ = rb.min.z, rMaxZ = rb.max.z

            let lift = SimulationConstants.matchLoaderLiftHeight
            let step = SimulationConstants.matchLoaderLiftRate * dt / max(lift, 0.001)

            for pair in pairs {
                let onLine =
                    rMinX <= pair.line.maxXZ.x && rMaxX >= pair.line.minXZ.x &&
                    rMinZ <= pair.line.maxXZ.y && rMaxZ >= pair.line.minXZ.y
                let target: Float = onLine ? 1 : 0

                // Rising edge — first frame the robot lands on this line.
                // Queue a delayed spawn so the loader has time to finish
                // rising; if we spawned immediately, the moving loader
                // would crash into the pin from below and fling it.
                if onLine && !pair.hasSpawnedThisVisit {
                    pair.pendingSpawnDelay = SimulationConstants.matchLoaderSpawnDelay
                    pair.hasSpawnedThisVisit = true
                } else if !onLine {
                    pair.hasSpawnedThisVisit = false
                    pair.pendingSpawnDelay = nil
                }

                if let delay = pair.pendingSpawnDelay {
                    let next = delay - dt
                    if next <= 0 {
                        // Spawn just above the *actual* top of the loader
                        // at rest. By this point the loader is settled at
                        // full lift, so the pin spawns clear of the mesh
                        // and falls onto / past it under gravity.
                        let spawnPos = SIMD3<Float>(
                            pair.visualCenter.x,
                            pair.loaderTopY + lift + 0.08,
                            pair.visualCenter.z
                        )
                        spawnPin(variant: pair.spawnVariant, at: spawnPos)
                        pair.pendingSpawnDelay = nil
                    } else {
                        pair.pendingSpawnDelay = next
                    }
                }

                pair.phase = approach(pair.phase, target: target, step: step)
                var p = pair.restWorldPos
                p.y += pair.phase * lift
                pair.loader.setPosition(p, relativeTo: nil)
            }
        }

        // Wipe spawned pins and snap matchloaders back to rest. Used by the
        // Reset button.
        @MainActor
        func reset() {
            if let group = spawnGroup {
                for child in Array(group.children) { child.removeFromParent() }
            }
            for pair in pairs {
                pair.phase = 0
                pair.hasSpawnedThisVisit = false
                pair.pendingSpawnDelay = nil
                pair.loader.setPosition(pair.restWorldPos, relativeTo: nil)
            }
        }

        // Clone a pin prefab from RCP and drop it at `worldPos` as a fresh
        // dynamic body with gravity on. Whatever physics the template had
        // (static/kinematic) gets overridden — spawned pins need to actually
        // fall onto the loader. The 0-restitution material is critical;
        // PhysicsBodyComponent.init(mode:) without a material uses
        // RealityKit defaults that bounce noticeably.
        @MainActor
        private func spawnPin(variant: PinVariant, at worldPos: SIMD3<Float>) {
            guard let template = pinTemplates[variant], let group = spawnGroup else { return }
            let clone = template.clone(recursive: true)
            clone.isEnabled = true
            clone.name = "Spawned_\(variant.rawValue)_\(group.children.count)"
            group.addChild(clone)
            clone.setPosition(worldPos, relativeTo: nil)
            clone.setOrientation(simd_quatf(angle: 0, axis: [0, 1, 0]), relativeTo: nil)

            var body = PhysicsBodyComponent(massProperties: .default,
                                            material: spawnedPinMaterial,
                                            mode: .dynamic)
            body.isAffectedByGravity = true
            body.angularDamping = 2.0
            body.linearDamping = 0.3
            clone.components.set(body)
        }

        private func inside(_ p: SIMD2<Float>, _ box: TapeAABB) -> Bool {
            p.x >= box.minXZ.x && p.x <= box.maxXZ.x &&
            p.y >= box.minXZ.y && p.y <= box.maxXZ.y
        }

        private func approach(_ current: Float, target: Float, step: Float) -> Float {
            if current < target { return min(current + step, target) }
            if current > target { return max(current - step, target) }
            return current
        }
    }

    // MARK: Physics debug overlay

    // Spawns a translucent green box mirroring each entity's visual bounds.
    // Attached to the same entity so the overlay tracks any movement.
    // NB: this visualizes *visual* bounds — most colliders match their mesh
    // but a few (e.g. the field rollers' oversized capsules) won't, so the
    // overlay doubles as a way to spot mesh/collider misalignment.
    @MainActor
    final class PhysicsDebugOverlay {
        private var overlayEntities: [Entity] = []
        private weak var root: Entity?

        @MainActor
        init(root: Entity) { self.root = root }

        @MainActor
        func show() {
            guard overlayEntities.isEmpty, let root = root else { return }
            walk(root) { entity in
                guard entity.components.has(CollisionComponent.self) else { return }
                let bounds = entity.visualBounds(relativeTo: entity)
                let size = bounds.max - bounds.min
                guard size.x > 0.001 || size.y > 0.001 || size.z > 0.001 else { return }
                let safe = SIMD3<Float>(max(size.x, 0.005),
                                        max(size.y, 0.005),
                                        max(size.z, 0.005))
                let mesh = MeshResource.generateBox(size: safe)
                var mat = UnlitMaterial(color: UIColor(red: 0.1, green: 1.0, blue: 0.2, alpha: 0.28))
                mat.blending = .transparent(opacity: .init(floatLiteral: 0.35))
                let dbg = ModelEntity(mesh: mesh, materials: [mat])
                dbg.name = "_PhysicsDebugBox"
                dbg.position = (bounds.max + bounds.min) * 0.5
                entity.addChild(dbg)
                overlayEntities.append(dbg)
            }
        }

        @MainActor
        func hide() {
            for e in overlayEntities { e.removeFromParent() }
            overlayEntities.removeAll()
        }
    }

    // MARK: Helpers

    @MainActor
    private static func walk(_ entity: Entity, _ visit: (Entity) -> Void) {
        visit(entity)
        for child in entity.children { walk(child, visit) }
    }
}
