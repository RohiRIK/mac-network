import MacNetworkCore
import SwiftUI

enum PanelTab: String, CaseIterable, Identifiable {
    case overview, wifi, ip
    var id: Self { self }
    var title: String {
        switch self {
        case .overview: "Overview"
        case .wifi: "Wi-Fi"
        case .ip: "IP Settings"
        }
    }
    var symbol: String {
        switch self {
        case .overview: "gauge.with.dots.needle.33percent"
        case .wifi: "wifi"
        case .ip: "slider.horizontal.3"
        }
    }
}

// MARK: Overview

struct OverviewTab: View {
    let model: NetworkModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let message = model.message {
                Text(message)
                    .font(.subheadline).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
            }
            if model.kind == .disconnected {
                ContentUnavailableView(model.wifiOn ? "Not Connected" : "Wi-Fi Is Off",
                                       systemImage: model.wifiOn ? "network.slash" : "wifi.slash",
                                       description: Text(model.wifiOn ? "Pick a network in the Wi-Fi tab." : "Turn it on in the Wi-Fi tab."))
                    .frame(height: 160)
            } else {
                ConnectionModule(model: model)
            }
            if model.needsLocation {
                LocationBanner(canPrompt: model.locationCanPrompt, action: model.requestLocation)
            }
        }
    }
}

// MARK: Wi-Fi

struct WiFiTab: View {
    @Bindable var model: NetworkModel
    @State var showOthers = true

    private var current: WiFiNetwork? { model.networks.first(where: \.connected) }
    private var known: [WiFiNetwork] { model.networks.filter { $0.known && !$0.connected } }
    private var others: [WiFiNetwork] { model.networks.filter { !$0.known && !$0.connected } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Wi-Fi").font(.headline)
                Spacer()
                if model.scanning { ProgressView().controlSize(.mini) }
                Toggle("Wi-Fi", isOn: Binding(get: { model.wifiOn }, set: { _ in model.toggleWiFi() }))
                    .toggleStyle(.switch).labelsHidden().controlSize(.small)
                    .help("Turn Wi-Fi on or off (W)")
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 6)

            if model.needsLocation {
                LocationBanner(canPrompt: model.locationCanPrompt, action: model.requestLocation)
                    .padding(.bottom, 6)
            }
            if model.wifiOn {
                if let current { networkRow(current) }
                if !known.isEmpty {
                    MenuSectionHeader(title: "Known Networks")
                    ForEach(known) { networkRow($0) }
                }
                MenuRow(action: { withAnimation(.snappy(duration: 0.2)) { showOthers.toggle() } }) {
                    Text("Other Networks").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        .rotationEffect(.degrees(showOthers ? 90 : 0))
                }
                if showOthers {
                    if others.isEmpty {
                        Text(model.scanning ? "Scanning…" : "No other networks")
                            .font(.subheadline).foregroundStyle(.secondary)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                    }
                    // No inner ScrollView: the panel scrolls each tab as a whole.
                    ForEach(others) { networkRow($0) }
                }
                MenuDivider()
                CommandRow(title: "Wi-Fi Settings…", action: model.openWiFiSettings)
            }
        }
    }

    @ViewBuilder private func networkRow(_ net: WiFiNetwork) -> some View {
        MenuRow(action: { model.select(net) }) {
            CircleIcon(symbol: "wifi", variableValue: Double(net.signal) / 100, active: net.connected)
            Text(net.ssid).lineLimit(1).truncationMode(.middle)
            Spacer()
            if model.connecting == net.ssid { ProgressView().controlSize(.mini) }
            if net.security.requiresCredentials {
                Image(systemName: "lock.fill").font(.caption).foregroundStyle(.secondary)
            }
        }
        .accessibilityValue("\(net.signal) percent signal\(net.connected ? ", connected" : "")")
        .contextMenu {
            if net.canForget { Button("Forget This Network…") { model.forget(net) } }
        }
        if model.passwordFor == net.ssid { PasswordField(network: net, model: model) }
        if let error = model.joinError, error.ssid == net.ssid {
            Text(error.text)
                .font(.subheadline).foregroundStyle(.red)
                .padding(.leading, 42).padding(.trailing, 8).padding(.bottom, 4)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct PasswordField: View {
    let network: WiFiNetwork
    let model: NetworkModel
    @State private var password = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 6) {
            SecureField("Password", text: $password)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onSubmit(join)
            Button("Join", action: join)
                .disabled(password.isEmpty)
                .keyboardShortcut(.defaultAction)
        }
        .controlSize(.small)
        .padding(.leading, 42).padding(.trailing, 8).padding(.vertical, 4)
        .onAppear { focused = true }
    }

    private func join() {
        guard !password.isEmpty else { return }
        model.join(network, password: password)
    }
}

// MARK: Footer

/// App commands only; everything else lives in the tabs or the Settings window.
struct PanelFooter: View {
    let model: NetworkModel
    let openSettings: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            MenuDivider()
            CommandRow(title: "Settings…", key: "⌘,", action: openSettings)
            CommandRow(title: "Quit Mac Network", key: "⌘Q", action: model.quit)
        }
    }
}

#Preview("Overview") {
    OverviewTab(model: .preview()).padding(6).frame(width: 340)
}

#Preview("Wi-Fi") {
    WiFiTab(model: .preview()).padding(6).frame(width: 340)
}
