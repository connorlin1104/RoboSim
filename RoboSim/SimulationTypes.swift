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

// MARK: - Pin Colors / Stance

// rawValue must match the asset filename prefix exactly, e.g.
// (top: .red, bottom: .blue) → "RedBluePin.usdz".
enum PinHalfColor: String {
    case red = "Red"
    case blue = "Blue"
    case yellow = "Yellow"
}

// How a spawned pin starts out — standing up or lying on its side.
enum PinStance {
    case vertical         // long axis along world Y (stands on its base)
    case verticalFlipped  // standing upside-down — top half ends up on the bottom
    case horizontal       // long axis horizontal — pin lies flat on the floor
}

// MARK: - Match Load Controller

// Lets the SwiftUI HUD enqueue match-load requests that the RealityKit
// scene-update closure processes on the next frame. Reference type so the
// closure and the button share state; @unchecked because both ends run on
// the main actor in practice.
final class MatchLoadController: @unchecked Sendable {
    var pendingRed: Int = 0
    var pendingBlue: Int = 0
}
