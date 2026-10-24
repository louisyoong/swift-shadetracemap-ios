import SwiftUI

enum ThemeMode { case system, light, dark }

private let accent: UInt32 = 0xFFFFB300
private let linkedInURL = URL(string: "https://www.linkedin.com/in/louis-yoong-a2370ab7")!

struct SettingsScreen: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(AppLanguage.self) private var language
    @Binding var themeMode: ThemeMode

    var body: some View {
        let isDark = scheme == .dark
        let panelTint: Color = isDark ? Color(hex: 0xFF15171C) : .white
        let label = Color.secondary
        let divider = Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1)

        GeometryReader { geo in
            // Keeps the cards a readable width on wide windows.
            let side = max(16, (geo.size.width - 640) / 2)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Settings")
                        .font(.system(size: 28, weight: .bold)).tracking(-0.5)
                    HStack(spacing: 14) {
                        Image("Logo").resizable().frame(width: 52, height: 52)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Shade Map Demo").font(.system(size: 16, weight: .bold))
                            Text("Real 3D buildings + computed sun-cast shadows, with a standalone sun-path simulator.")
                                .font(.system(size: 12)).foregroundStyle(label).lineSpacing(3)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .glass(radius: kCardRadius, tint: panelTint, opacity: 0.55)
                    .padding(.top, 20)

                    SectionLabel("APPEARANCE", color: label).padding(.leading, 4).padding(.bottom, 8).padding(.top, 28)
                    VStack(spacing: 0) {
                        themeOption("circle.lefthalf.filled", "System", "Match your device setting", .system, isDark)
                        divider
                        themeOption("sun.max.fill", "Light", nil, .light, isDark)
                        divider
                        themeOption("moon.fill", "Dark", nil, .dark, isDark)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .glass(radius: kCardRadius, tint: panelTint, opacity: 0.55)

                    SectionLabel("LANGUAGE", color: label).padding(.leading, 4).padding(.bottom, 8).padding(.top, 28)
                    languagePicker(isDark)
                        .glass(radius: kCardRadius, tint: panelTint, opacity: 0.55)

                    SectionLabel("ABOUT", color: label).padding(.leading, 4).padding(.bottom, 8).padding(.top, 28)
                    VStack(spacing: 0) {
                        infoRow("info.circle", "Version",
                                Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
                                isDark)
                        divider
                        infoRow("heart", "Made for sun-chasers", "☀️", isDark)
                        divider
                        Button { UIApplication.shared.open(linkedInURL) } label: {
                            row("link", "Contact via LinkedIn", isDark) {
                                Image(systemName: "chevron.right").font(.system(size: 13)).foregroundStyle(label)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 4)
                    .glass(radius: kCardRadius, tint: panelTint, opacity: 0.55)
                }
                .padding(EdgeInsets(top: 20, leading: side, bottom: 16, trailing: side))
            }
        }
        .background(LinearGradient(colors: isDark ? [Color(hex: 0xFF171922), Color(hex: 0xFF0A0B0E)]
                                                  : [Color(hex: 0xFFEAF2FF), Color(hex: 0xFFF7F8FA)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing).ignoresSafeArea())
    }

    /// A dropdown of every supported language, each in its own name, plus
    /// "System" to follow the device.
    private func languagePicker(_ isDark: Bool) -> some View {
        let current = language.code.flatMap { code in AppLanguage.options.first { $0.code == code }?.name }
        return Menu {
            Button { language.set(nil) } label: {
                if language.code == nil { Label("System", systemImage: "checkmark") } else { Text("System") }
            }
            Divider()
            ForEach(AppLanguage.options, id: \.code) { option in
                Button { language.set(option.code) } label: {
                    if language.code == option.code {
                        Label(option.name, systemImage: "checkmark")
                    } else {
                        Text(verbatim: option.name)
                    }
                }
            }
        } label: {
            row("globe", "Language", isDark) {
                HStack(spacing: 4) {
                    if let current { Text(verbatim: current) } else { Text("System") }
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 11, weight: .semibold))
                }
                .font(.system(size: 14))
                .foregroundStyle(accentForTheme(accent, isDark))
            }
        }
        .buttonStyle(.plain)
        .padding(.vertical, 4)
    }

    private func badge(_ icon: String, _ isDark: Bool, size: CGFloat = 30) -> some View {
        Image(systemName: icon)
            .font(.system(size: 14))
            .foregroundStyle(badgeIconColor(accent, isDark))
            .frame(width: size, height: size)
            .background(Circle().fill(badgeBackground(accent, isDark)))
    }

    private func row<T: View>(_ icon: String, _ text: LocalizedStringKey, _ isDark: Bool, @ViewBuilder trailing: () -> T) -> some View {
        HStack(spacing: 12) {
            badge(icon, isDark)
            Text(text).font(.system(size: 14))
            Spacer()
            trailing()
        }
        .padding(12)
        .contentShape(Rectangle())
    }

    private func infoRow(_ icon: String, _ text: LocalizedStringKey, _ value: String, _ isDark: Bool) -> some View {
        row(icon, text, isDark) { Text(value).font(.system(size: 14)).foregroundStyle(.secondary) }
    }

    private func themeOption(_ icon: String, _ text: LocalizedStringKey, _ subtitle: LocalizedStringKey?, _ mode: ThemeMode, _ isDark: Bool) -> some View {
        let selected = themeMode == mode
        return Button { themeMode = mode } label: {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 17))
                    .foregroundStyle(selected ? badgeIconColor(accent, isDark) : Color.primary)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(selected ? badgeBackground(accent, isDark) : Color.primary.opacity(0.14)))
                VStack(alignment: .leading, spacing: 0) {
                    Text(text).font(.system(size: 16, weight: .semibold))
                    if let subtitle { Text(subtitle).font(.system(size: 12)).foregroundStyle(.secondary) }
                }
                Spacer()
                if selected {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 19))
                        .foregroundStyle(accentForTheme(accent, isDark))
                }
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
