import MacNetworkCore
import SwiftUI

/// IP Settings tab: System Settings > Network > Details > TCP/IP wording and grouped look,
/// built from SettingsGroup/SettingsRow so it sizes to content inside the menu panel.
struct IPSettingsTab: View {
    var settings: IPSettings? = IPSettings()

    @State var services: [NetworkService] = []
    @State var selected: NetworkService?
    @State var method: IPMethod = .dhcp
    @State var address = ""
    @State var mask = ""
    @State var router = ""
    @State var dns = ""
    @State private var saved: IPConfig?
    @State private var note: String?
    @State private var error: String?
    @State private var busy = false

    private var config: IPConfig {
        let prefix = IPv4.prefix(mask: mask.trimmingCharacters(in: .whitespaces))
        let cidr = address.isEmpty ? "" : prefix.map { "\(address)/\($0)" } ?? "\(address)/invalid"
        return IPConfig(service: selected?.name ?? "", method: method, address: cidr, gateway: router, dns: dns)
    }

    private var dirty: Bool { saved != nil && config != saved }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsGroup {
                SettingsRow(title: "Connection", subtitle: selected.map { "Interface \($0.device)" }) {
                    Picker("Connection", selection: $selected) {
                        ForEach(services) { Text($0.name).tag(Optional($0)) }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 150)
                }
            }

            SettingsGroup(title: "IPv4") {
                SettingsRow(title: "Configure", subtitle: method == .dhcp ? "Router assigns the address" : "Fixed address") {
                    Picker("Configure IPv4", selection: $method) {
                        Text("Using DHCP").tag(IPMethod.dhcp)
                        Text("Manually").tag(IPMethod.manual)
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                RowDivider()
                valueRow("IP address", $address, "192.168.1.50")
                RowDivider()
                valueRow("Subnet mask", $mask, "255.255.255.0")
                RowDivider()
                valueRow("Router", $router, "192.168.1.1")
                if method == .manual {
                    RowDivider()
                    SettingsRow(title: "Start from current") {
                        Button("Use Current", action: fillCurrent)
                            .controlSize(.small)
                            .disabled(selected == nil || busy)
                    }
                }
            }

            SettingsGroup(title: "DNS") {
                SettingsRow(title: "Servers", subtitle: "Empty uses DHCP") {
                    field($dns, "From DHCP")
                }
            }

            footer
        }
        .task { await load() }
        // task(id:) cancels the previous read when the service changes, so a slow older read
        // cannot overwrite the newer one.
        .task(id: selected) { if let selected { await read(selected) } }
    }

    /// Editable in manual mode; plain text in DHCP mode (disabled fields look broken).
    @ViewBuilder private func valueRow(_ title: String, _ text: Binding<String>, _ prompt: String) -> some View {
        SettingsRow(title: title) {
            if method == .manual {
                field(text, prompt)
            } else {
                Text(text.wrappedValue.isEmpty ? "—" : text.wrappedValue)
                    .foregroundStyle(.secondary).monospacedDigit().textSelection(.enabled)
            }
        }
    }

    private func field(_ text: Binding<String>, _ prompt: String) -> some View {
        TextField(prompt, text: text, prompt: Text(prompt))
            .labelsHidden()
            .textFieldStyle(.plain)
            .multilineTextAlignment(.trailing)
            .monospacedDigit()
            .frame(maxWidth: 140)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Group {
                if let error {
                    Text(error).foregroundStyle(.red)
                } else if let note {
                    Text(note).foregroundStyle(.secondary)
                } else if busy {
                    ProgressView().controlSize(.small)
                }
            }
            .font(.caption)
            .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button("Revert") { if let saved { apply(saved) } }
                .disabled(!dirty || busy)
            Button("Apply…", action: save)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!dirty || busy || selected == nil)
                .help("macOS asks for your administrator password")
        }
        .controlSize(.small)
        .padding(.horizontal, 4)
    }

    // MARK: Data

    private func apply(_ c: IPConfig) {
        method = c.method
        let cidr = IPv4.parseCIDR(c.address)
        address = cidr?.address ?? ""
        mask = cidr.map { IPv4.mask(prefix: $0.prefix) } ?? ""
        router = c.gateway
        dns = c.dns
    }

    private func load() async {
        guard let settings else { return }
        do {
            services = try await settings.services()
            selected = await settings.activeService(in: services) ?? services.first
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func read(_ service: NetworkService) async {
        guard let settings else { return }
        error = nil; note = nil
        do {
            apply(try await settings.read(service))
            saved = config
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func fillCurrent() {
        guard let settings, let selected else { return }
        busy = true
        Task {
            defer { busy = false }
            do {
                apply(try await settings.current(selected))
                error = nil
                note = "Filled in from the current connection. Review, then Apply."
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private func save() {
        guard let settings else { return }
        if method == .manual, IPv4.prefix(mask: mask) == nil {
            error = "Enter a valid subnet mask, such as 255.255.255.0"
            return
        }
        busy = true
        error = nil
        Task {
            defer { busy = false }
            do {
                try await settings.save(config, services: services)
                saved = config
                note = "Applied."
            } catch let e as ShellError where e.message == "Cancelled" {
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

#Preview("Manual") {
    let wifi = NetworkService(name: "Wi-Fi", device: "en0")
    IPSettingsTab(settings: nil,
                  services: [wifi, NetworkService(name: "Triple-display Mini Docking sta", device: "en13")],
                  selected: wifi, method: .manual,
                  address: "192.0.2.50", mask: "255.255.255.0", router: "192.0.2.1", dns: "1.1.1.1")
        .padding(6).frame(width: 340)
}

#Preview("DHCP") {
    let wifi = NetworkService(name: "Wi-Fi", device: "en0")
    IPSettingsTab(settings: nil, services: [wifi], selected: wifi, method: .dhcp,
                  address: "192.0.2.24", mask: "255.255.255.0", router: "192.0.2.1")
        .padding(6).frame(width: 340)
}
