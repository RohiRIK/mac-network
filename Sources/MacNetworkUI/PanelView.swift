import AppKit
import MacNetworkCore
import SwiftUI

/// Panel root: CodexBar-style tab switcher (Overview · Wi-Fi · IP Settings), the selected tab,
/// and the shared footer. Everything lives in the menu bar panel; no extra windows.
/// Keys: 1-3 or S switch tabs, R refresh, W Wi-Fi, Esc close, ⌘Q quit.
public struct PanelView: View {
    let model: NetworkModel
    @State var tab: PanelTab

    public init(model: NetworkModel) {
        self.model = model
        _tab = State(initialValue: .overview)
    }

    init(model: NetworkModel, tab: PanelTab) {
        self.model = model
        _tab = State(initialValue: tab)
    }

    /// Fits the tallest normal tab (IP Settings, Overview with the Location banner) without scrolling.
    static let contentHeight: CGFloat = 350

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openSettings) private var openSettings
    @AppStorage(Prefs.theme) private var theme: AppTheme = .system
    @AppStorage(Prefs.accent) private var accent: AccentChoice = .system
    @FocusState private var focused: Bool

    /// A menu bar app is never active; activate first or Settings opens behind other windows.
    private func showSettings() {
        dismiss()
        NSApp.activate()
        openSettings()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TabSwitcher(tabs: PanelTab.allCases, selection: $tab, title: \.title, symbol: \.symbol)
            // Every tab gets the same height so the panel never resizes or jumps when switching;
            // anything taller scrolls inside the tab.
            ScrollView {
                Group {
                    switch tab {
                    case .overview: OverviewTab(model: model)
                    case .wifi: WiFiTab(model: model)
                    case .ip: IPSettingsTab()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(height: Self.contentHeight)
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.automatic)
            PanelFooter(model: model, openSettings: showSettings)
        }
        .padding(8)
        .frame(width: 340)
        // Report the full content height as ideal size. Without it the MenuBarExtra window keeps an
        // old height when content grows (banner appears, tab changes), clipping and overlapping rows.
        .fixedSize(horizontal: false, vertical: true)
        .themed(theme, accent)
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onAppear { focused = true; model.panelOpen = true }
        .onDisappear { model.panelOpen = false }
        .onKeyPress(.escape) {
            dismiss()
            return .handled
        }
        .onKeyPress(keys: ["q", ","]) { press in
            guard press.modifiers.contains(.command) else { return .ignored }
            if press.key == "q" { model.quit() } else { showSettings() }
            return .handled
        }
        .onKeyPress(characters: .init(charactersIn: "123srw")) { press in
            guard press.modifiers.isEmpty else { return .ignored }
            switch press.characters {
            case "1": tab = .overview
            case "2": tab = .wifi
            case "3", "s": tab = .ip
            case "r": model.refreshNow(rescan: true)
            case "w": model.toggleWiFi()
            default: return .ignored
            }
            return .handled
        }
    }
}

#Preview("Overview") {
    PanelView(model: .preview())
}

#Preview("Wi-Fi tab") {
    PanelView(model: .preview(), tab: .wifi)
}

#Preview("Light") {
    PanelView(model: .preview()).preferredColorScheme(.light)
}

#Preview("Name hidden") {
    PanelView(model: .preview(nameHidden: true))
}

#Preview("IP Settings tab") {
    PanelView(model: .preview(), tab: .ip)
}
