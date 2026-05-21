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

// MARK: - HUD Overlay

struct HUDOverlay: View {
    @Binding var leftStickOffset: CGSize
    @Binding var rightStickOffset: CGSize
    @Binding var cameraMode: CameraMode
    let matchLoad: MatchLoadController

    var body: some View {
        VStack {
            HStack {
                // Red alliance match-load button. Each press enqueues one
                // red pin to fly in from the west loader onto the field.
                Button {
                    matchLoad.pendingRed += 1
                } label: {
                    Text("Load Red")
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.red.opacity(0.85))
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
                .padding(.leading, 16)
                .padding(.top, 16)

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

                Spacer()

                // Blue alliance match-load button. Mirrors the red one.
                Button {
                    matchLoad.pendingBlue += 1
                } label: {
                    Text("Load Blue")
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.blue.opacity(0.85))
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
                .padding(.trailing, 16)
                .padding(.top, 16)
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
}
