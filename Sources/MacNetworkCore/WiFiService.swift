import CoreLocation
import CoreWLAN
import Foundation
import Observation

/// Live Wi-Fi link details for the header and details grid.
public struct WiFiLink: Sendable, Equatable {
    public var ssid: String?     // nil until Location access is granted
    public var signal: Int       // 0...100
    public var rssi: Int         // dBm
    public var txRateMbps: Double
    public var band: String      // "2.4ghz", "5ghz", "6ghz", ""
    public var device: String

    public init(ssid: String?, signal: Int, rssi: Int, txRateMbps: Double, band: String, device: String) {
        self.ssid = ssid
        self.signal = signal
        self.rssi = rssi
        self.txRateMbps = txRateMbps
        self.band = band
        self.device = device
    }
}

/// CoreWLAN wrapper: scan, join, forget (admin), power, link details.
/// An actor, so every CoreWLAN call (XPC to airportd, scans take 1-3 s) runs off the main thread
/// and one at a time. SSIDs read as nil on macOS 14+ until the app has Location authorization.
public actor WiFiService {
    private let client = CWWiFiClient.shared()

    public init() {}

    private var iface: CWInterface? { client.interface() }

    public func isPoweredOn() -> Bool { iface?.powerOn() ?? false }

    public func setPower(_ on: Bool) throws {
        try iface?.setPower(on)
    }

    public func link() -> WiFiLink? {
        guard let i = iface, i.powerOn(), i.wlanChannel() != nil else { return nil }
        return WiFiLink(
            ssid: i.ssid(),
            signal: Self.signalPercent(rssi: i.rssiValue()),
            rssi: i.rssiValue(),
            txRateMbps: i.transmitRate(),
            band: Self.band(i.wlanChannel()?.channelBand),
            device: i.interfaceName ?? "en0"
        )
    }

    /// Scans (1-3 s), merges known profiles, sorts like the source.
    public func scan() throws -> [WiFiNetwork] {
        guard let i = iface else { return [] }
        let known = Set((i.configuration()?.networkProfiles.array as? [CWNetworkProfile] ?? []).compactMap(\.ssid))
        let current = i.ssid()
        var best: [String: CWNetwork] = [:]
        for net in try i.scanForNetworks(withName: nil) {
            guard let ssid = net.ssid, !ssid.isEmpty else { continue }
            if (best[ssid]?.rssiValue ?? .min) < net.rssiValue { best[ssid] = net }
        }
        let rows = best.map { ssid, net in
            WiFiNetwork(ssid: ssid, signal: Self.signalPercent(rssi: net.rssiValue),
                        connected: ssid == current, known: known.contains(ssid),
                        security: Self.security(net))
        }
        return WiFiList.sorted(rows)
    }

    /// Passphrase stays in-process; never on argv.
    public func connect(ssid: String, password: String?) throws {
        guard let i = iface,
              let net = try i.scanForNetworks(withName: ssid).max(by: { $0.rssiValue < $1.rssiValue })
        else { throw ShellError("Network not found") }
        try i.associate(to: net, password: password)
    }

    /// Joins a saved network with its stored password. CoreWLAN cannot read the system
    /// keychain entry, so `associate(to:password: nil)` fails for secured known networks;
    /// `networksetup` joins with the saved credentials. It reports failure on stdout, exit 0.
    public func joinKnown(ssid: String, run: @escaping Runner = Shell.run) async throws {
        let device = iface?.interfaceName ?? "en0"
        let out = try await run("/usr/sbin/networksetup", ["-setairportnetwork", device, ssid])
        if let failure = Self.joinFailure(out) { throw ShellError(failure) }
    }

    static func joinFailure(_ out: String) -> String? {
        let text = out.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        return text.localizedCaseInsensitiveContains("error") || text.localizedCaseInsensitiveContains("could not")
            || text.localizedCaseInsensitiveContains("failed") ? text : nil
    }

    public func disconnect() {
        iface?.disassociate()
    }

    /// Removes a saved network. Needs admin, so it shows the macOS password prompt.
    public func forget(ssid: String) async throws {
        let device = iface?.interfaceName ?? "en0"
        try await Shell.runAsAdmin(tool: "/usr/sbin/networksetup",
                                   commands: [["-removepreferredwirelessnetwork", device, ssid]])
    }

    // MARK: Pure (tested)

    /// -90 dBm or worse = 0 %, -30 dBm or better = 100 %, linear between.
    public static func signalPercent(rssi: Int) -> Int {
        min(100, max(0, (rssi + 90) * 100 / 60))
    }

    static func band(_ band: CWChannelBand?) -> String {
        switch band {
        case .band2GHz: "2.4ghz"
        case .band5GHz: "5ghz"
        case .band6GHz: "6ghz"
        default: ""
        }
    }

    static func security(_ net: CWNetwork) -> WiFiSecurity {
        if net.supportsSecurity(.none) { return .open }
        if net.supportsSecurity(.OWE) || net.supportsSecurity(.oweTransition) { return .owe }
        if [.enterprise, .wpaEnterprise, .wpa2Enterprise, .wpa3Enterprise].contains(where: net.supportsSecurity) { return .enterprise }
        if [.personal, .wpaPersonal, .wpa2Personal, .wpa3Personal, .WEP].contains(where: net.supportsSecurity) { return .personal }
        return .unknown
    }
}

/// Asks for Location access, which macOS requires before CoreWLAN returns SSIDs.
/// @Observable so Settings and onboarding update the moment the user answers the prompt.
@MainActor @Observable
public final class LocationAccess: NSObject, CLLocationManagerDelegate {
    @ObservationIgnored private let manager = CLLocationManager()
    public private(set) var status: CLAuthorizationStatus

    public override init() {
        status = manager.authorizationStatus
        super.init()
        manager.delegate = self
    }

    /// Only "Always" counts. A menu bar app is never "in use", so When-In-Use authorization
    /// (status 4) still leaves CoreWLAN SSIDs nil. Verified in locationd logs (InUse:0).
    public var granted: Bool { status == .authorizedAlways }

    /// True while macOS can still show its prompt; afterwards only System Settings can change it.
    public var canPrompt: Bool { status == .notDetermined }

    public func request() {
        manager.requestAlwaysAuthorization()
    }

    nonisolated public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in self.status = status }
    }
}
