import SwiftUI

private let sunAccent = Color(hex: 0xFFFFD580)

/// First-launch-only welcome screen: the branded graphic edge to edge, with
/// "Get Started" overlaid near the bottom.
struct OnboardingScreen: View {
    let onGetStarted: () -> Void
    @State private var loading = false

    var body: some View {
        ZStack(alignment: .bottom) {
            // In an overlay so the fill-scaled image never widens the layout.
            // The artwork is phone-shaped: on wide windows (iPad, iPhone Duo
            // inner display) filling would blow the logo up, so it's fitted
            // to the height instead, over its own edge colors with the sides
            // faded so no seam shows.
            GeometryReader { geo in
                let wide = geo.size.width >= 600
                LinearGradient(colors: [Color(hex: 0xFF0F141B), Color(hex: 0xFF141821), Color(hex: 0xFF0E1219)],
                               startPoint: .top, endPoint: .bottom)
                    .overlay {
                        if wide {
                            Image("Onboarding").resizable().scaledToFit()
                                .mask(LinearGradient(stops: [.init(color: .clear, location: 0),
                                                             .init(color: .black, location: 0.12),
                                                             .init(color: .black, location: 0.88),
                                                             .init(color: .clear, location: 1)],
                                                     startPoint: .leading, endPoint: .trailing))
                        } else {
                            Image("Onboarding").resizable().scaledToFill()
                        }
                    }
                    .clipped()
            }
            .ignoresSafeArea()
            LinearGradient(stops: [.init(color: .black.opacity(0), location: 0.55),
                                   .init(color: .black.opacity(0.55), location: 1)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
                .allowsHitTesting(false)
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
            .frame(maxWidth: 420)
            .padding(EdgeInsets(top: 0, leading: 32, bottom: 28, trailing: 32))
            // Centered on the whole screen like the artwork, not just the safe
            // area - the iPhone Duo outer display reserves a side column.
            .frame(maxWidth: .infinity)
            .ignoresSafeArea(.container, edges: .horizontal)
        }
    }

    /// A short loading beat gives the map tab a head start on its style
    /// fetch while the user is still looking at this screen.
    private func getStarted() {
        loading = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: onGetStarted)
    }
}
