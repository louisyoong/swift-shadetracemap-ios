import SwiftUI

/// Place search with saved places: the pin saves `current` and opens the
/// Saved Places page, and focusing the field lists them to jump to.
struct LocationSearchField: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(SavedPlaces.self) private var saved
    @Bindable var controller: LocationSearchController
    let onSelect: (Place) -> Void
    var hint: LocalizedStringKey = "Search any place worldwide…"
    /// The place the screen is showing now; nil hides the star.
    var current: Place?

    @FocusState private var focused: Bool
    /// The place the star just saved; non-nil shows the Saved Places page.
    @State private var savedPage: SavedPageItem?

    private struct SavedPageItem: Identifiable {
        let id = UUID()
        let highlighted: UUID?
    }

    var body: some View {
        let isDark = scheme == .dark
        let tint = isDark ? Color(hex: 0xFF15171C) : Color(hex: 0xFFE9EBEE)
        let text = isDark ? Color(hex: 0xFFF2F2F2) : Color(hex: 0xFF1B1D22)
        let muted = isDark ? Color(hex: 0xFF9AA0A8) : Color(hex: 0xFF6B7078)

        VStack(spacing: 6) {
            HStack(spacing: 8) {
                HStack(spacing: 0) {
                    TextField("", text: $controller.text, prompt: Text(hint).foregroundStyle(muted))
                        .font(.system(size: 13.5))
                        .foregroundStyle(text)
                        .tint(kBlue)
                        .focused($focused)
                        .submitLabel(.search)
                        .autocorrectionDisabled()
                        .onSubmit { controller.submit(onSelect) }
                        .onKeyPress(.escape) {
                            controller.clear()
                            return .handled
                        }
                    if controller.searching {
                        ProgressView()
                            .controlSize(.mini)
                            .tint(muted)
                            .padding(.leading, 6)
                    } else if !controller.text.isEmpty {
                        Button(action: controller.clear) {
                            Image(systemName: "xmark")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(muted)
                                .frame(width: 28, height: 28)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.leading, 14)
                .padding(.trailing, controller.searching || !controller.text.isEmpty ? 6 : 14)
                .frame(height: 42)
                .glass(radius: 11, tint: tint, opacity: 0.75)
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .stroke(kBlue, lineWidth: focused ? 1.4 : 0)
                )

                if let current {
                    saveButton(current, tint: tint, muted: muted)
                }
            }

            if !controller.results.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(controller.results) { place in
                            Button {
                                focused = false
                                onSelect(place)
                            } label: {
                                Text(place.displayName)
                                    .font(.system(size: 11.5))
                                    .lineSpacing(2)
                                    .foregroundStyle(text)
                                    .multilineTextAlignment(.leading)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 7)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(5)
                }
                .scrollBounceBehavior(.basedOnSize)
                .frame(maxHeight: 220)
                .fixedSize(horizontal: false, vertical: true)
                .glass(radius: 11, tint: tint, opacity: 0.78)
            } else if focused && !saved.places.isEmpty {
                savedList(text: text, muted: muted, tint: tint)
            }
        }
        .sheet(item: $savedPage) { item in
            SavedPlacesPage(highlighted: item.highlighted, onSelect: onSelect)
        }
    }

    /// A round glass button beside the field with the pin, gold once saved.
    private func saveButton(_ current: Place, tint: Color, muted: Color) -> some View {
        let isSaved = saved.saved(lat: current.lat, lon: current.lon) != nil
        return Button {
            focused = false
            // Already saved: just open the list (remove from there).
            savedPage = SavedPageItem(highlighted: isSaved ? nil : saved.save(current).id)
        } label: {
            Image(systemName: "mappin.and.ellipse")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(isSaved ? kGold : muted)
                .frame(width: 42, height: 42)
                .glass(circle: true, tint: tint, opacity: 0.75)
                .overlay(Circle().stroke(kGold.opacity(isSaved ? 0.6 : 0), lineWidth: 1.2))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isSaved ? Text("Saved Places") : Text("Save this place"))
    }

    private func savedList(text: Color, muted: Color, tint: Color) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("SAVED PLACES")
                    .font(.system(size: 10, weight: .semibold)).tracking(0.6)
                    .foregroundStyle(muted)
                    .padding(.horizontal, 9)
                    .padding(.top, 4)
                    .padding(.bottom, 2)
                ForEach(saved.places) { place in
                    HStack(spacing: 0) {
                        Button {
                            focused = false
                            onSelect(place.place)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "mappin.and.ellipse").font(.system(size: 11)).foregroundStyle(kGold)
                                Text(place.name)
                                    .font(.system(size: 12.5, weight: .medium))
                                    .foregroundStyle(text)
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .padding(.leading, 9)
                            .padding(.vertical, 9)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Button { saved.remove(place) } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(muted)
                                .frame(width: 32, height: 32)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text("Remove from saved places"))
                    }
                }
            }
            .padding(5)
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxHeight: 220)
        .fixedSize(horizontal: false, vertical: true)
        .glass(radius: 11, tint: tint, opacity: 0.78)
    }
}
