import SwiftUI

// MARK: - Joystick

struct JoystickView: View {
    @Binding var offset: CGSize
    var axis: JoystickAxis

    static let trackRadius: CGFloat = 60
    private let thumbSize: CGFloat = 44

    var body: some View {
        ZStack {
            Circle()
                .fill(.black.opacity(0.25))
                .frame(width: Self.trackRadius * 2, height: Self.trackRadius * 2)

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
        guard len > Self.trackRadius else { return CGSize(width: x, height: y) }
        let scale = Self.trackRadius / len
        return CGSize(width: x * scale, height: y * scale)
    }
}

// MARK: - VEX-style buttons

// Circular hold-to-activate button. All buttons render in the same neutral
// translucent style — no per-button colors — so the HUD stays out of the way.
struct VEXButton: View {
    let label: String
    @Binding var isPressed: Bool
    var size: CGFloat = 46

    var body: some View {
        ZStack {
            Circle()
                .fill(.white.opacity(isPressed ? 0.32 : 0.10))
            Circle()
                .stroke(.white.opacity(isPressed ? 0.85 : 0.35), lineWidth: 1.5)
            Text(label)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(isPressed ? 0.95 : 0.55))
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in if !isPressed { isPressed = true } }
                .onEnded   { _ in isPressed = false }
        )
    }
}

// Rounded-rectangle shoulder button (L1/L2/R1/R2). Same translucent style as
// the face buttons, just a different shape to match a real V5 controller.
struct VEXShoulderButton: View {
    let label: String
    @Binding var isPressed: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(.white.opacity(isPressed ? 0.32 : 0.10))
            RoundedRectangle(cornerRadius: 6)
                .stroke(.white.opacity(isPressed ? 0.85 : 0.35), lineWidth: 1.5)
            Text(label)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(isPressed ? 0.95 : 0.55))
        }
        .frame(width: 52, height: 28)
        .contentShape(RoundedRectangle(cornerRadius: 6))
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in if !isPressed { isPressed = true } }
                .onEnded   { _ in isPressed = false }
        )
    }
}

// Face-button diamond (X top / Y left / B right / A bottom) — mirrors a V5
// controller's right cluster. Bindings flow back to the drive loop.
struct VEXButtonCluster: View {
    @Binding var armUp: Bool
    @Binding var armDown: Bool
    @Binding var intakeIn: Bool
    @Binding var intakeOut: Bool

    private let buttonSpacing: CGFloat = 50

    var body: some View {
        ZStack {
            VEXButton(label: "X", isPressed: $armUp)
                .offset(y: -buttonSpacing)
            VEXButton(label: "Y", isPressed: $intakeIn)
                .offset(x: -buttonSpacing)
            VEXButton(label: "B", isPressed: $intakeOut)
                .offset(x:  buttonSpacing)
            VEXButton(label: "A", isPressed: $armDown)
                .offset(y:  buttonSpacing)
        }
        .frame(width: buttonSpacing * 2 + 46, height: buttonSpacing * 2 + 46)
    }
}

// D-pad cluster — same diamond layout as the face cluster, but using arrows.
// Currently visual-only (no robot behavior wired). Press state is owned by
// the parent so wiring up actions later is just connecting the bindings.
struct DPadCluster: View {
    @Binding var up: Bool
    @Binding var down: Bool
    @Binding var left: Bool
    @Binding var right: Bool

    private let buttonSpacing: CGFloat = 44

    var body: some View {
        ZStack {
            VEXButton(label: "▲", isPressed: $up,    size: 40).offset(y: -buttonSpacing)
            VEXButton(label: "◀", isPressed: $left,  size: 40).offset(x: -buttonSpacing)
            VEXButton(label: "▶", isPressed: $right, size: 40).offset(x:  buttonSpacing)
            VEXButton(label: "▼", isPressed: $down,  size: 40).offset(y:  buttonSpacing)
        }
        .frame(width: buttonSpacing * 2 + 40, height: buttonSpacing * 2 + 40)
    }
}

// MARK: - HUD Overlay

struct HUDOverlay: View {
    @Binding var leftStickOffset: CGSize
    @Binding var rightStickOffset: CGSize
    @Binding var cameraMode: CameraMode
    @Binding var armUp: Bool
    @Binding var armDown: Bool
    @Binding var intakeIn: Bool
    @Binding var intakeOut: Bool
    @Binding var physicsDebug: Bool

    // Buttons that exist on a V5 controller but aren't wired to robot
    // behavior yet — kept as local state. Hook them up to DriveInput as you
    // decide what they should do.
    @State private var l1 = false
    @State private var l2 = false
    @State private var r1 = false
    @State private var r2 = false
    @State private var dpadUp = false
    @State private var dpadDown = false
    @State private var dpadLeft = false
    @State private var dpadRight = false

    var body: some View {
        VStack {
            topRow
            Spacer()
            bottomRow
        }
    }

    private var topRow: some View {
        HStack(alignment: .top) {
            VStack(spacing: 8) {
                VEXShoulderButton(label: "L1", isPressed: $l1)
                VEXShoulderButton(label: "L2", isPressed: $l2)
            }
            .padding(.leading, 24)
            .padding(.top, 18)

            Spacer()

            HStack(spacing: 12) {
                cameraToggleButton
                physicsToggleButton
            }
            .padding(.top, 14)

            Spacer()

            VStack(spacing: 8) {
                VEXShoulderButton(label: "R1", isPressed: $r1)
                VEXShoulderButton(label: "R2", isPressed: $r2)
            }
            .padding(.trailing, 24)
            .padding(.top, 18)
        }
    }

    private var cameraToggleButton: some View {
        Button {
            cameraMode = (cameraMode == .thirdPerson) ? .firstPerson : .thirdPerson
        } label: {
            Text(cameraMode == .thirdPerson ? "1st Person" : "3rd Person")
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial)
                .cornerRadius(8)
        }
    }

    private var physicsToggleButton: some View {
        Button {
            physicsDebug.toggle()
        } label: {
            Text(physicsDebug ? "Hide Physics" : "Show Physics")
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial)
                .cornerRadius(8)
        }
    }

    private var bottomRow: some View {
        HStack(alignment: .bottom) {
            HStack(spacing: 24) {
                JoystickView(offset: $leftStickOffset, axis: .vertical)
                DPadCluster(up: $dpadUp, down: $dpadDown,
                            left: $dpadLeft, right: $dpadRight)
            }
            .padding(.leading, 60)
            .padding(.bottom, 60)

            Spacer()

            HStack(spacing: 24) {
                VEXButtonCluster(armUp: $armUp,
                                 armDown: $armDown,
                                 intakeIn: $intakeIn,
                                 intakeOut: $intakeOut)
                JoystickView(offset: $rightStickOffset, axis: .horizontal)
            }
            .padding(.trailing, 60)
            .padding(.bottom, 60)
        }
    }
}
