import SwiftUI

// The App Store ID from the public README link (apps.apple.com/.../id6792345460).
private let appStoreReviewURL = URL(string: "https://apps.apple.com/app/id6792345460?action=write-review")!
private let hasRatedKey = "has_rated_app"

enum AppRating {
    static var hasRated: Bool { UserDefaults.standard.bool(forKey: hasRatedKey) }

    static func submit() {
        UserDefaults.standard.set(true, forKey: hasRatedKey)
        UIApplication.shared.open(appStoreReviewURL)
    }
}

/// Mirrors Apple's own "Enjoying [App]? Tap a star to rate it" prompt: five
/// stars that fill up to the tapped one and auto-dismiss shortly after. A
/// custom dialog instead of SKStoreReviewController because Apple doesn't
/// tell the app whether a review was left, and the app needs to know so it
/// can stop asking - same reasoning as the Flutter version.
struct RatingDialog: View {
    @Binding var isPresented: Bool
    @State private var selectedStars: Int?

    private let starAccent = Color(hex: 0xFFFFB300)

    var body: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()
            VStack(spacing: 0) {
                VStack(spacing: 10) {
                    Image("Logo")
                        .resizable()
                        .frame(width: 52, height: 52)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    Text("Enjoying ShadeTrace Map?")
                        .font(.headline)
                    Text("Tap a star to rate it on the App Store.")
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                    HStack(spacing: 6) {
                        ForEach(1...5, id: \.self) { star in
                            Image(systemName: star <= (selectedStars ?? 0) ? "star.fill" : "star")
                                .font(.system(size: 24))
                                .foregroundStyle(starAccent)
                                .onTapGesture { select(star) }
                        }
                    }
                    .padding(.top, 2)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 18)
                Divider()
                Button("Not Now") { isPresented = false }
                    .font(.body)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .frame(width: 270)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private func select(_ stars: Int) {
        guard selectedStars == nil else { return }
        selectedStars = stars
        Task {
            try? await Task.sleep(for: .milliseconds(350))
            isPresented = false
            AppRating.submit()
        }
    }
}
