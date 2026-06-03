import SwiftUI

struct HomeView: View {
    @EnvironmentObject var ble: BLEManager
    @State private var isInteractingWithModel = false

    let isActive: Bool

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.black,
                    Color(hue: 0.58, saturation: 0.50, brightness: 0.28)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            RadialGradient(
                colors: [Color.cyan.opacity(0.14), Color.clear],
                center: .center,
                startRadius: 20,
                endRadius: 360
            )
            .ignoresSafeArea()

            VStack {
                VStack(spacing: 8) {
                    Text("ARIS")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .kerning(6)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.white, Color.cyan.opacity(0.7)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                    Text("Augmented Reality Integrated System")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(Color.white.opacity(0.7))
                }
                .padding(.top, 80)

                Spacer()

                VStack(spacing: 12) {
                    FrameModelView(isInteracting: $isInteractingWithModel)
                        .frame(width: 320, height: 300)

                    Text("Drag to rotate")
                        .font(.footnote)
                        .foregroundStyle(Color.white.opacity(0.6))
                }

                Spacer()

                VStack(spacing: 6) {
                    Image(systemName: "arrow.left.and.right")
                        .font(.title3)
                        .foregroundStyle(Color.white.opacity(0.6))

                    Text("Swipe to Explore")
                        .font(.footnote)
                        .foregroundStyle(Color.white.opacity(0.6))
                }
                .padding(.bottom, 60)
            }
        }
        .onAppear {
            sendHomeModeIfNeeded()
        }
        .onChange(of: isActive) { _, _ in
            sendHomeModeIfNeeded()
        }
        .onChange(of: ble.isConnected) { _, _ in
            sendHomeModeIfNeeded()
        }
    }

    private func sendHomeModeIfNeeded() {
        guard isActive, ble.isConnected else { return }
        ble.send("HOME:ARIS|\(ble.isConnected ? "CONNECTED" : "DISCONNECTED")|HOME")
    }
}
