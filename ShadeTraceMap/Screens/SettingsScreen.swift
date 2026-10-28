import SwiftUI

enum ThemeMode { case system, light, dark }

private let accent: UInt32 = 0xFFFFB300
private let linkedInURL = URL(string: "https://www.linkedin.com/in/louis-yoong-a2370ab7")!

struct SettingsScreen: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(AppLanguage.self) private var language
    @Environment(SavedPlaces.self) private var saved
    @Environment(GoldenHourReminders.self) private var reminders
    @Binding var themeMode: ThemeMode
    /// Bottom safe area outside and inside the NavigationStack. The stack
    /// drops the extra inset RootView adds for the floating tab bar, so
    /// the difference is added back - otherwise the end of the page (and of
    /// pushed pages) stays hidden behind the bar.
    @State private var outerBottom: CGFloat = 0
    @State private var innerBottom: CGFloat = 0
    private var tabBarGap: CGFloat { max(0, outerBottom - innerBottom) }

    var body: some View {
        let isDark = scheme == .dark
        let panelTint: Color = isDark ? Color(hex: 0xFF15171C) : .white
        let label = Color.secondary
        let divider = Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1)

        // A navigation stack so Saved Places can be pushed and come back with
        // the back button; this page keeps its own large title, so the bar
        // only shows on pushed pages.
        NavigationStack {
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

                        SectionLabel("GOLDEN HOUR REMINDERS", color: label).padding(.leading, 4).padding(.bottom, 8).padding(.top, 28)
                        remindersCard(isDark, divider: divider)
                            .glass(radius: kCardRadius, tint: panelTint, opacity: 0.55)

                        SectionLabel("SAVED PLACES", color: label).padding(.leading, 4).padding(.bottom, 8).padding(.top, 28)
                        NavigationLink {
                            SavedPlacesPage(inSheet: false)
                            .safeAreaPadding(.bottom, tabBarGap)
                        } label: {
                            row("mappin.and.ellipse", "Saved Places", isDark) {
                                HStack(spacing: 6) {
                                    Text(verbatim: "\(saved.places.count)")
                                        .font(.system(size: 14)).foregroundStyle(.secondary)
                                    Image(systemName: "chevron.right").font(.system(size: 13)).foregroundStyle(label)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, 4)
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
                .safeAreaPadding(.bottom, tabBarGap)
                .onAppear { innerBottom = geo.safeAreaInsets.bottom }
                .onChange(of: geo.safeAreaInsets.bottom) { _, inset in innerBottom = inset }
            }
            .background(LinearGradient(colors: isDark ? [Color(hex: 0xFF171922), Color(hex: 0xFF0A0B0E)]
                                                      : [Color(hex: 0xFFEAF2FF), Color(hex: 0xFFF7F8FA)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing).ignoresSafeArea())
            // Names the back button on pushed pages ("‹ Settings").
            .navigationTitle(Text("Settings"))
            .toolbar(.hidden, for: .navigationBar)
        }
        .tint(accentForTheme(accent, isDark))
        .background {
            GeometryReader { outer in
                Color.clear
                    .onAppear { outerBottom = outer.safeAreaInsets.bottom }
                    .onChange(of: outer.safeAreaInsets.bottom) { _, inset in outerBottom = inset }
            }
        }
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

    private func remindersCard(_ isDark: Bool, divider: some View) -> some View {
        VStack(spacing: 0) {
            row("bell", "Golden hour reminders", isDark) {
                Toggle("", isOn: Binding(get: { reminders.enabled },
                                         set: { on in Task { await reminders.setEnabled(on) } }))
                    .labelsHidden()
                    .tint(accentForTheme(accent, isDark))
            }
            if reminders.permissionDenied {
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                } label: {
                    Text("Notifications are off for ShadeTrace Map. Tap to turn them on in Settings.")
                        .font(.system(size: 12))
                        .foregroundStyle(accentForTheme(accent, isDark))
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(EdgeInsets(top: 0, leading: 54, bottom: 12, trailing: 12))
                }
                .buttonStyle(.plain)
            }
            if reminders.enabled {
                divider
                menuRow("clock", "Remind me", isDark, value: Text("\(reminders.leadMinutes) min before")) {
                    ForEach(GoldenHourReminders.leadOptions, id: \.self) { minutes in
                        checkButton(reminders.leadMinutes == minutes, Text("\(minutes) min before")) {
                            reminders.leadMinutes = minutes
                        }
                    }
                }
                divider
                let place = reminders.placeId.flatMap { saved.place(id: $0) }
                menuRow("mappin.and.ellipse", "Place", isDark,
                        value: place.map { Text(verbatim: $0.name) } ?? Text("My Location")) {
                    checkButton(place == nil, Text("My Location")) { reminders.placeId = nil }
                    if !saved.places.isEmpty {
                        Divider()
                        ForEach(saved.places) { p in
                            checkButton(place?.id == p.id, Text(verbatim: p.name)) { reminders.placeId = p.id }
                        }
                    }
                }
                divider
                row("sunrise", "Morning golden hour too", isDark) {
                    Toggle("", isOn: Binding(get: { reminders.includeMorning }, set: { reminders.includeMorning = $0 }))
                        .labelsHidden()
                        .tint(accentForTheme(accent, isDark))
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func menuRow<Items: View>(_ icon: String, _ text: LocalizedStringKey, _ isDark: Bool, value: Text,
                                      @ViewBuilder items: () -> Items) -> some View {
        Menu {
            items()
        } label: {
            row(icon, text, isDark) {
                HStack(spacing: 4) {
                    value.lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 11, weight: .semibold))
                }
                .font(.system(size: 14))
                .foregroundStyle(accentForTheme(accent, isDark))
            }
        }
        .buttonStyle(.plain)
    }

    private func checkButton(_ checked: Bool, _ title: Text, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            if checked { Label { title } icon: { Image(systemName: "checkmark") } } else { title }
        }
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
