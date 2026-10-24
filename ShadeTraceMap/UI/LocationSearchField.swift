import SwiftUI

struct LocationSearchField: View {
    @Environment(\.colorScheme) private var scheme
    @Bindable var controller: LocationSearchController
    let onSelect: (Place) -> Void
    var hint: LocalizedStringKey = "Search any place worldwide…"

    @FocusState private var focused: Bool

    var body: some View {
        let isDark = scheme == .dark
        let tint = isDark ? Color(hex: 0xFF15171C) : Color(hex: 0xFFE9EBEE)
        let text = isDark ? Color(hex: 0xFFF2F2F2) : Color(hex: 0xFF1B1D22)
        let muted = isDark ? Color(hex: 0xFF9AA0A8) : Color(hex: 0xFF6B7078)

        VStack(spacing: 6) {
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
            }
        }
    }
}
