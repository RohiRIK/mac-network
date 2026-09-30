import AppKit
import SwiftUI

public let onboardingWindowID = "onboarding"

// MARK: Shared permission rows (Settings › Permissions and onboarding)

/// Location: status on the left, the one action that can change it on the right.
struct LocationPermissionRow: View {
    let model: NetworkModel

    var body: some View {
        SettingsRow(title: "Location", subtitle: subtitle) {
            switch model.locationState {
            case .granted:
                Label("Allowed", systemImage: "checkmark.circle.fill")
                    .labelStyle(.titleAndIcon).foregroundStyle(.green)
            case .notDetermined:
                Button("Allow", action: model.requestLocation).buttonStyle(.borderedProminent)
            case .whenInUse, .denied:
                Button("Open Settings…", action: model.requestLocation)
            }
        }
    }

    private var subtitle: String {
        switch model.locationState {
        case .granted: "Wi-Fi names are visible."
        case .notDetermined: "macOS shows Wi-Fi names only with Location access."
        case .whenInUse: "Set to While Using. Choose Always so the menu bar app can read Wi-Fi names."
        case .denied: "Turn Mac Network on in Location Services."
        }
    }
}

struct LoginItemRow: View {
    let model: NetworkModel

    var body: some View {
        SettingsRow(title: "Open at Login", subtitle: "Start Mac Network when you log in.") {
            Toggle("Open at Login", isOn: Binding(get: { model.opensAtLogin }, set: model.setOpensAtLogin))
                .toggleStyle(.switch).labelsHidden().controlSize(.small)
        }
    }
}

struct AdminNoteRow: View {
    var body: some View {
        SettingsRow(title: "Administrator password",
                    subtitle: "Applying IP settings or forgetting a network asks for it each time. Nothing is stored.") {
            Image(systemName: "lock.shield").foregroundStyle(.secondary)
        }
    }
}

// MARK: Settings window

/// ⌘, Settings window with General, Permissions and Appearance tabs (CodexBar-style Preferences,
/// github.com/steipete/CodexBar, MIT). Network features stay in the menu bar panel.
public struct SettingsView: View {
    let model: NetworkModel
    @AppStorage(Prefs.theme) private var theme: AppTheme = .system
    @AppStorage(Prefs.accent) private var accent: AccentChoice = .system

    public init(model: NetworkModel) {
        self.model = model
    }

    public var body: some View {
        TabView {
            GeneralPane(model: model)
                .tabItem { Label("General", systemImage: "gearshape") }
            PermissionsPane(model: model)
                .tabItem { Label("Permissions", systemImage: "hand.raised") }
            AppearancePane()
                .tabItem { Label("Appearance", systemImage: "paintpalette") }
        }
        // 580 pt so row descriptions fit on one line (MacUX/MenuPanel.md › Settings window size).
        .frame(width: 580)
        .fixedSize(horizontal: false, vertical: true)
        .themed(theme, accent)
    }
}

private struct GeneralPane: View {
    let model: NetworkModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 14) {
            SettingsGroup(title: "Startup") {
                LoginItemRow(model: model)
            }
            SettingsGroup(title: "Help") {
                SettingsRow(title: "Welcome screen", subtitle: "Walk through permissions again.") {
                    Button("Show…") {
                        NSApp.activate()
                        openWindow(id: onboardingWindowID)
                    }
                }
            }
        }
        .padding(20)
    }
}

private struct PermissionsPane: View {
    let model: NetworkModel

    var body: some View {
        VStack(spacing: 14) {
            SettingsGroup(title: "Needed") {
                LocationPermissionRow(model: model)
            }
            SettingsGroup(title: "Asked when used") {
                AdminNoteRow()
            }
        }
        .padding(20)
    }
}

private struct AppearancePane: View {
    @AppStorage(Prefs.theme) private var theme: AppTheme = .system
    @AppStorage(Prefs.accent) private var accent: AccentChoice = .system

    var body: some View {
        VStack(spacing: 14) {
            SettingsGroup(title: "Theme") {
                SettingsRow(title: "Appearance", subtitle: "Applies to the panel and these windows.") {
                    Picker("Appearance", selection: $theme) {
                        ForEach(AppTheme.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden().pickerStyle(.segmented).fixedSize()
                }
                RowDivider()
                SettingsRow(title: "Accent color", subtitle: accent.title) {
                    AccentSwatches(selection: $accent)
                }
            }
        }
        .padding(20)
    }
}

/// Round color swatches like System Settings > Appearance > Accent color.
private struct AccentSwatches: View {
    @Binding var selection: AccentChoice

    var body: some View {
        HStack(spacing: 6) {
            ForEach(AccentChoice.allCases) { choice in
                Button { selection = choice } label: {
                    Circle()
                        .fill(choice.color.map { AnyShapeStyle($0) }
                              ?? AnyShapeStyle(AngularGradient(colors: [.red, .yellow, .green, .blue, .purple, .red], center: .center)))
                        .frame(width: 16, height: 16)
                        .overlay {
                            if selection == choice {
                                Circle().fill(.white).frame(width: 6, height: 6)
                            }
                        }
                }
                .buttonStyle(.plain)
                .help(choice.title)
                .accessibilityLabel(choice.title)
                .accessibilityAddTraits(selection == choice ? .isSelected : [])
            }
        }
    }
}

// MARK: Onboarding

/// Shown once on first launch (and from Settings › General). Asks only for what the app needs.
public struct OnboardingView: View {
    let model: NetworkModel
    @AppStorage(Prefs.onboarded) private var onboarded = false
    @AppStorage(Prefs.theme) private var theme: AppTheme = .system
    @AppStorage(Prefs.accent) private var accent: AccentChoice = .system
    @Environment(\.dismiss) private var dismiss

    public init(model: NetworkModel) {
        self.model = model
    }

    public var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 10) {
                Image(systemName: "network")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 64, height: 64)
                    .background(.tint, in: .rect(cornerRadius: 16, style: .continuous))
                Text("Welcome to Mac Network").font(.title2.weight(.semibold))
                Text("Your network at a glance, in the menu bar. It needs one permission to show Wi-Fi names.")
                    .font(.callout).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 8)

            SettingsGroup {
                LocationPermissionRow(model: model)
                RowDivider()
                LoginItemRow(model: model)
                RowDivider()
                AdminNoteRow()
            }

            HStack {
                Text("Change these any time in Settings (⌘,).").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Continue") {
                    onboarded = true
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
        .themed(theme, accent)
        // A menu bar app is never active; bring the welcome window to the front.
        .onAppear { NSApp.activate() }
    }
}

#Preview("Onboarding") {
    OnboardingView(model: .preview())
}

#Preview("Settings") {
    SettingsView(model: .preview())
}

#Preview("Appearance") {
    AppearancePane().frame(width: 460)
}
