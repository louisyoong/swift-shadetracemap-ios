import SwiftUI

private let sunAccent = Color(hex: 0xFFFFD580)

/// First-launch-only welcome screen: the branded graphic edge to edge, with
/// the tagline and "Get Started" overlaid near the bottom.
struct OnboardingScreen: View {
    let onGetStarted: () -> Void
    @State private var loading = false

    var body: some View {
        ZStack(alignment: .bottom) {
            // In an overlay so the fill-scaled image never widens the layout.
            Color.black
                .overlay { Image("Onboarding").resizable().scaledToFill() }
                .clipped()
                .ignoresSafeArea()
            LinearGradient(stops: [.init(color: .black.opacity(0), location: 0.55),
                                   .init(color: .black.opacity(0.55), location: 1)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
                .allowsHitTesting(false)
            VStack(spacing: 28) {
                Text("Find real-time shade and\nsun exposure anywhere in\nthe world.")
                    .font(.system(size: 22, weight: .semibold))
                    .tracking(-0.2)
                    .lineSpacing(5)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                Button(action: getStarted) {
                    Group {
                        if loading {
                            ProgressView().tint(Color(hex: 0xFF2A2620))
                        } else {
                            HStack(spacing: 8) {
                                Text("Get Started").font(.system(size: 16.5, weight: .bold))
                                Image(systemName: "arrow.right").font(.system(size: 17, weight: .semibold))
                            }
                        }
                    }
                    .foregroundStyle(Color(hex: 0xFF2A2620))
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .background(Capsule().fill(sunAccent))
                }
                .buttonStyle(.plain)
                .disabled(loading)
            }
            .frame(maxWidth: 420)
            .padding(EdgeInsets(top: 0, leading: 32, bottom: 28, trailing: 32))
        }
    }

    /// A short loading beat gives the map tab a head start on its style
    /// fetch while the user is still looking at this screen.
    private func getStarted() {
        loading = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: onGetStarted)
    }
}
