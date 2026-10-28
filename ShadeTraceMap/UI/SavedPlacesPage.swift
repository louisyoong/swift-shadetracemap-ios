import SwiftUI

/// The full list of saved places; the trash removes one.
///
/// From the pin beside a search bar it's a sheet (`inSheet`) with a Done
/// button, and tapping a place goes there - a full-height page on iPhone and
/// the iPhone Duo, a centered card on iPad. From Settings it's pushed onto
/// the navigation stack (back returns to Settings) and is just the listing.
struct SavedPlacesPage: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss
    @Environment(SavedPlaces.self) private var saved
    /// The place just saved, highlighted with a "Saved" note.
    var highlighted: UUID?
    /// nil makes the rows a plain listing (Settings has no map to go to).
    var onSelect: ((Place) -> Void)?
    var inSheet = true

    var body: some View {
        if inSheet {
            NavigationStack {
                list
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { dismiss() }.tint(kGold)
                        }
                    }
            }
            .presentationDetents([.large])
        } else {
            list
        }
    }

    private var list: some View {
        let isDark = scheme == .dark
        let panelTint: Color = isDark ? Color(hex: 0xFF15171C) : .white
        return ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let highlighted, let place = saved.place(id: highlighted) {
                    Label {
                        Text("Saved “\(place.name)” to your places.")
                    } icon: {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(kGold)
                    }
                    .font(.system(size: 13, weight: .medium))
                    .padding(.horizontal, 4)
                }
                if saved.places.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "mappin.and.ellipse").font(.system(size: 30)).foregroundStyle(kGold)
                        Text("No saved places yet").font(.system(size: 16, weight: .semibold))
                        Text("Tap the pin next to any search bar to save a place.")
                            .font(.system(size: 13)).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 48)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(saved.places.enumerated()), id: \.element.id) { index, place in
                            if index > 0 {
                                Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1).padding(.leading, 56)
                            }
                            row(place, isDark, isNew: place.id == highlighted)
                        }
                    }
                    .padding(.vertical, 4)
                    .glass(radius: kCardRadius, tint: panelTint, opacity: 0.55)
                }
            }
            .padding(16)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .background(LinearGradient(colors: isDark ? [Color(hex: 0xFF171922), Color(hex: 0xFF0A0B0E)]
                                                  : [Color(hex: 0xFFEAF2FF), Color(hex: 0xFFF7F8FA)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing).ignoresSafeArea())
        .navigationTitle(Text("Saved Places"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ place: SavedPlace, _ isDark: Bool, isNew: Bool) -> some View {
        HStack(spacing: 12) {
            if let onSelect {
                Button {
                    onSelect(place.place)
                    dismiss()
                } label: { info(place, isDark, isNew: isNew) }
                .buttonStyle(.plain)
            } else {
                info(place, isDark, isNew: isNew)
            }
            Button { withAnimation { saved.remove(place) } } label: {
                Image(systemName: "trash")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Remove from saved places"))
        }
        .padding(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 8))
        .background(isNew ? kGold.opacity(0.10) : .clear)
    }

    private func info(_ place: SavedPlace, _ isDark: Bool, isNew: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "mappin.and.ellipse")
                .font(.system(size: 14))
                .foregroundStyle(badgeIconColor(0xFFFFB300, isDark))
                .frame(width: 32, height: 32)
                .background(Circle().fill(badgeBackground(0xFFFFB300, isDark)))
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: place.name)
                    .font(.system(size: 15, weight: isNew ? .semibold : .regular))
                    .foregroundStyle(Color.primary)
                    .lineLimit(2)
                Text(verbatim: String(format: "%.4f, %.4f", place.lat, place.lon))
                    .font(.system(size: 11)).foregroundStyle(.secondary).monospacedDigit()
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }
}
