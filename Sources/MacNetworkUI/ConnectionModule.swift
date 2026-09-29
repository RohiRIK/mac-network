import MacNetworkCore
import SwiftUI

/// The current connection as a Control Center-style module: a softly filled rounded tile with
/// the network, a 2×2 grid of live stats, and the addresses. Standard fills only (HIG: no glass
/// on content), no borders or shadows.
struct ConnectionModule: View {
    let model: NetworkModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            stats
            addresses
        }
        .padding(12)
        .background(.quinary, in: .rect(cornerRadius: 12, style: .continuous))
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            CircleIcon(symbol: model.kind.symbolName,
                       variableValue: model.kind == .wifi ? model.signal : nil, active: true, size: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text(model.title).font(.body.weight(.semibold)).lineLimit(1).truncationMode(.middle)
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
            }
            Spacer(minLength: 8)
            if model.kind == .wifi, model.networks.first(where: \.connected)?.security.requiresCredentials == true {
                Image(systemName: "lock.fill").font(.caption).foregroundStyle(.tertiary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String {
        guard model.kind == .wifi, let link = model.link else { return model.headerDetail }
        return [model.headerDetail, "\(Int(link.txRateMbps)) Mbit/s", "\(link.rssi) dBm"]
            .filter { !$0.isEmpty }.joined(separator: " · ")
    }

    // MARK: Stats

    private var stats: some View {
        let hasRouter = !model.ping.router.isEmpty
        let hasInternet = !model.ping.internet.isEmpty
        return Grid(horizontalSpacing: 8, verticalSpacing: 8) {
            GridRow {
                StatCell(symbol: "wifi.router", title: "Router",
                         value: Model.formatPingLatency(model.ping.routerLatency, hasSamples: hasRouter),
                         health: health(model.ping.routerLatency, hasRouter, good: 20, fair: 80))
                StatCell(symbol: "globe", title: "Internet",
                         value: Model.formatPingLatency(model.ping.internetLatency, hasSamples: hasInternet),
                         detail: hasInternet ? "\(Model.formatPacketLoss(model.ping.internetPacketLoss, hasSamples: true)) loss" : nil,
                         health: model.ping.internetPacketLoss > 0 ? .fair
                             : health(model.ping.internetLatency, hasInternet, good: 60, fair: 150))
            }
            GridRow {
                StatCell(symbol: "arrow.down", title: "Download",
                         value: Model.formatRate(model.throughput.downloadRate))
                StatCell(symbol: "arrow.up", title: "Upload",
                         value: Model.formatRate(model.throughput.uploadRate))
            }
        }
    }

    private func health(_ ms: Double?, _ hasSamples: Bool, good: Double, fair: Double) -> StatCell.Health? {
        guard hasSamples else { return nil }
        guard let ms else { return .poor }
        return ms <= good ? .good : ms <= fair ? .fair : .poor
    }

    // MARK: Addresses

    private var addresses: some View {
        VStack(spacing: 6) {
            AddressRow(label: "IP address", value: model.address.isEmpty ? "--" : model.address)
            AddressRow(label: "Router", value: model.gateway ?? "--")
            HStack {
                Text("Public IP").foregroundStyle(.secondary)
                Spacer()
                publicIP
            }
        }
        .font(.subheadline)
    }

    @ViewBuilder private var publicIP: some View {
        switch model.publicIP {
        case .idle:
            Button("Look Up", action: model.lookUpPublicIP)
                .buttonStyle(.link)
                .help("Asks api.ipify.org for your public IPv4 address")
        case .loading:
            ProgressView().controlSize(.mini)
        case .value(let ip):
            Text(ip).monospacedDigit().textSelection(.enabled)
        case .failed(let reason):
            Button("\(reason) · Retry", action: model.lookUpPublicIP).buttonStyle(.link)
        }
    }
}

/// One live number: small symbol + caption, then the value; optional health dot.
struct StatCell: View {
    enum Health {
        case good, fair, poor
        var color: Color { self == .good ? .green : self == .fair ? .orange : .red }
        var label: String { self == .good ? "good" : self == .fair ? "fair" : "poor" }
    }

    let symbol: String
    let title: String
    let value: String
    var detail: String?
    var health: Health?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: symbol).font(.caption2.weight(.semibold))
                Text(title).font(.caption)
                Spacer(minLength: 0)
                if let health {
                    Circle().fill(health.color).frame(width: 6, height: 6)
                }
            }
            .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value).font(.callout.weight(.semibold)).monospacedDigit().lineLimit(1)
                if let detail { Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quinary, in: .rect(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityValue(health.map { "\(value), \($0.label)" } ?? value)
    }
}

private struct AddressRow: View {
    let label: String
    let value: String
    var body: some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).monospacedDigit().lineLimit(1).textSelection(.enabled)
        }
    }
}

/// Shown when macOS hides Wi-Fi names. First time it triggers the prompt; after a decision macOS
/// never prompts again, so the button opens System Settings instead.
struct LocationBanner: View {
    let canPrompt: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "location.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.tint)
                .frame(width: 28, height: 28)
                .background(.tint.opacity(0.15), in: .circle)
            VStack(alignment: .leading, spacing: 1) {
                Text("Network names are hidden").font(.subheadline.weight(.semibold))
                Text("Allow Location so macOS shares them.").font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button(canPrompt ? "Allow" : "Settings…", action: action)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .help(canPrompt ? "Shows the macOS Location prompt"
                                : "Opens System Settings > Privacy & Security > Location Services")
        }
        .padding(10)
        .background(.tint.opacity(0.08), in: .rect(cornerRadius: 12, style: .continuous))
    }
}

#Preview("Module, Wi-Fi") {
    ConnectionModule(model: .preview()).padding(6).frame(width: 320)
}

#Preview("Location banner") {
    VStack {
        LocationBanner(canPrompt: true, action: {})
        LocationBanner(canPrompt: false, action: {})
    }
    .padding(6).frame(width: 320)
}
