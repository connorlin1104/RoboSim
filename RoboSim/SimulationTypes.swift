import Foundation

// MARK: - Simulation Constants

// Knobs that need to be visible to more than one builder (robot drive loop,
// camera clamp, respawn logic). Keep tuning here — there's no other source
// of truth for these values.
enum SimulationConstants {
    static let thirdPersonPosition: SIMD3<Float> = [-3, 4, 3]   // NW perspective
    static let joystickRadius: CGFloat = 60
    static let maxLinearSpeed:  Float = 1.0      // m/s
    static let maxAngularSpeed: Float = 2.0      // rad/s
    static let wheelRadius:     Float = 0.06     // also = robot half-height
    static let chassisWidth:    Float = 0.3
    static let chassisHeight:   Float = 0.08
    static let chassisLength:   Float = 0.4
    static let wheelThickness:  Float = 0.04
    static let respawnThreshold: Float = -2
    static let minCameraY:      Float = 0.4      // keep orbit cam above the floor

    // Field-shape knobs — used by every field-element builder.
    static let fieldSize:      Float = 3.65      // VEX 12' x 12' tile field (m)
    static let wallHeight:     Float = 0.3
    static let wallThickness:  Float = 0.05
    static var halfField:      Float { fieldSize / 2 }
    static var tileSize:       Float { fieldSize / 6 }

    // Arm geometry & motion (kinematic — pure pose updates, no joint physics).
    static let armPivotForwardOffset: Float = -0.18  // -Z is forward
    static let armPivotHeight:        Float = 0.10
    static let armLength:             Float = 0.22
    static let armBarThickness:       Float = 0.02
    static let armMinAngle:           Float = -0.15  // rad, slightly above horizontal
    static let armMaxAngle:           Float = 1.35   // rad, nearly straight up
    static let armSlewRate:           Float = 2.5    // rad/s
    static let intakeRollerRadius:    Float = 0.025
    static let intakeRollerLength:    Float = 0.16
    static let intakeSpinRate:        Float = 12.0   // rad/s

    // Matchloader lift animation.
    static let matchLoaderLiftHeight: Float = 0.27   // m
    static let matchLoaderLiftRate:   Float = 1.5    // m/s
    static let matchLoaderSpawnDelay: Float = 0.5    // s — wait for lift to finish before dropping a pin
    static let tapeDetectInflateXZ:   Float = 0.08   // m, slop around line AABB
}

// MARK: - Drive Input (shared between SwiftUI and RealityKit)

final class DriveInput: @unchecked Sendable {
    var forward: Float = 0
    var turn: Float = 0
    var armUp: Bool = false       // X — hold to raise arm; releasing freezes
    var armDown: Bool = false     // A — hold to lower arm; releasing freezes
    var intakeIn: Bool = false    // Y — hold to spin roller inward
    var intakeOut: Bool = false   // B — hold to spin roller outward
    var resetRequested: Bool = false  // one-shot: drive loop consumes & clears
}

// MARK: - Joystick

enum JoystickAxis {
    case vertical
    case horizontal
}
