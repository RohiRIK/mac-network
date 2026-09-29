import MacNetworkUI
import SwiftUI

@main
struct MacNetworkApp: App {
    @State private var model = NetworkModel()
    @AppStorage("onboarded") private var onboarded = false

    var body: some Scene {
        MenuBarExtra {
            PanelView(model: model)
        } label: {
            // Distinct from Apple's Wi-Fi icon so the two are never confused in the menu bar.
            Image(systemName: model.kind == .disconnected ? "network.slash" : "network")
                .accessibilityLabel("Network: \(model.title)")
        }
        .menuBarExtraStyle(.window)

        // First launch only: asks for Location and Open at Login. Reopen from Settings › General.
        Window("Welcome to Mac Network", id: onboardingWindowID) {
            OnboardingView(model: model)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .defaultLaunchBehavior(onboarded ? .suppressed : .presented)

        Settings {
            SettingsView(model: model)
        }
        .windowResizability(.contentSize)
    }
}
