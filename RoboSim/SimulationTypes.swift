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
}

// MARK: - Drive Input (shared between SwiftUI and RealityKit)

final class DriveInput: @unchecked Sendable {
    var forward: Float = 0
    var turn: Float = 0
}

// MARK: - Joystick

enum JoystickAxis {
    case vertical
    case horizontal
}
