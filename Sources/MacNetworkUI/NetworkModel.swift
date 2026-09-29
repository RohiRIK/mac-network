import AppKit
import MacNetworkCore
import Observation
import os
import ServiceManagement

let log = Logger(subsystem: "local.macplugins.mac-network", category: "panel")

/// Panel state. Polls fast (1.5 s) while the panel is open, slowly (10 s) for the menu bar icon.
@MainActor @Observable
public final class NetworkModel {
    enum PublicIPState: Equatable { case idle, loading, value(String), failed(String) }

    public var kind: ConnectionKind = .disconnected
    var iface = ""
    var address = ""
    var gateway: String?
    var link: WiFiLink?
    var ethernetMbps: Int?
    var wifiOn = true
    var networks: [WiFiNetwork] = []
    var scanning = false
    var throughput = Throughput()
    var ping = PingStats(window: 5, averageWindow: 20)
    var publicIP: PublicIPState = .idle
    var needsLocation = false
    var locationCanPrompt = true
    var previewLocationState: LocationState = .notDetermined
    var message: String?
    var connecting: String?
    var passwordFor: String?
    var joinError: (ssid: String, text: String)?
    var opensAtLogin = false

    var panelOpen = false {
        didSet { if panelOpen != oldValue { refreshNow(rescan: panelOpen) } }
    }

    private let wifi: WiFiService?
    private let probe = LinkProbe()
    private let location: LocationAccess?
    private var lastScan = Date.distantPast
    private var pollTask: Task<Void, Never>?

    public init(live: Bool = true) {
        wifi = live ? WiFiService() : nil
        location = live ? LocationAccess() : nil
        guard live else { return }
        opensAtLogin = SMAppService.mainApp.status == .enabled
        refreshNow()
    }

    /// The only place refresh/scan run: one loop, restarted on open/close, key R, or after an
    /// action. Restarting (instead of calling refresh() alongside) prevents overlapping refreshes
    /// that double-count throughput and pings, and switches to the fast cadence immediately.
    func refreshNow(rescan: Bool = false) {
        guard wifi != nil else { return }
        if rescan { lastScan = .distantPast }
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refresh()
                if self.panelOpen, Date().timeIntervalSince(self.lastScan) > 15 { await self.scan() }
                try? await Task.sleep(for: self.panelOpen ? .seconds(1.5) : .seconds(10))
            }
        }
    }

    // MARK: Derived

    public var title: String {
        switch kind {
        case .wifi: link?.ssid ?? "Network name hidden"
        case .ethernet: "Ethernet"
        case .disconnected: wifiOn ? "Not connected" : "Wi-Fi off"
        }
    }

    var headerDetail: String {
        switch kind {
        case .wifi: link.map { $0.band.replacingOccurrences(of: "ghz", with: " GHz") } ?? ""
        case .ethernet: ethernetMbps.map { $0 < 1000 ? "\($0) Mbit/s" : "\((Double($0) / 1000).formatted()) Gbit/s" } ?? ""
        case .disconnected: ""
        }
    }

    public var signal: Double { Double(link?.signal ?? 0) / 100 }

    // MARK: Actions

    private func refresh() async {
        guard let wifi else { return }  // preview: keep fake data
        wifiOn = await wifi.isPoweredOn()
        link = await wifi.link()
        if let location {
            needsLocation = !location.granted && link != nil
            locationCanPrompt = location.canPrompt
        }

        guard let route = await probe.defaultRoute() else {
            kind = .disconnected
            iface = ""; address = ""; gateway = nil
            return
        }
        kind = route.iface == link?.device ? .wifi : .ethernet
        if route.iface != iface { ping = PingStats(window: 5, averageWindow: 20) }
        iface = route.iface
        gateway = route.gateway

        let sample = LinkProbe.sample(route.iface)
        address = sample.address ?? ""
        throughput = throughput.next(iface: route.iface, rxBytes: sample.rxBytes, txBytes: sample.txBytes,
                                     now: Date().timeIntervalSince1970)
        guard panelOpen else { return }  // closed: the menu bar icon needs only kind + signal
        ethernetMbps = kind == .ethernet ? await probe.ethernetSpeed(route.iface) : nil
        async let router: Probe? = gateway == nil ? nil : probe.ping(gateway!)
        async let internet = probe.ping("1.1.1.1")
        ping = ping.next(iface: route.iface, router: await router, internet: await internet)
    }

    private func scan() async {
        guard let wifi, wifiOn, !scanning else { return }
        scanning = true
        defer { scanning = false; lastScan = Date() }
        do {
            networks = try await wifi.scan()
            log.debug("scan: \(self.networks.count) networks, location=\(self.needsLocation ? "missing" : "ok", privacy: .public)")
        } catch {
            log.error("scan failed: \(error.localizedDescription, privacy: .public)")
            message = error.localizedDescription
        }
    }

    enum LocationState { case granted, notDetermined, whenInUse, denied }

    /// Live (observable) Location authorization for Settings and onboarding.
    var locationState: LocationState {
        guard let location else { return previewLocationState }
        switch location.status {
        case .authorizedAlways: return .granted
        case .notDetermined: return .notDetermined
        case .authorizedWhenInUse: return .whenInUse
        default: return .denied
        }
    }

    /// First time: the macOS prompt. After a decision macOS never prompts again, so open Settings.
    func requestLocation() {
        guard let location else { return }
        log.info("location status=\(location.status.rawValue, privacy: .public)")
        if location.canPrompt {
            location.request()
        } else {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices")!)
        }
    }

    func toggleWiFi() {
        guard let wifi else { return }
        let target = !wifiOn
        message = nil
        Task {
            do {
                try await wifi.setPower(target)
                wifiOn = target
                if !target { networks = [] }
                refreshNow(rescan: target)
            } catch {
                message = "Could not turn Wi-Fi \(target ? "on" : "off"): \(error.localizedDescription)"
            }
        }
    }

    func select(_ net: WiFiNetwork) {
        guard !net.connected, connecting == nil else { return }
        joinError = nil
        if net.security.requiresCredentials && !net.known {
            passwordFor = passwordFor == net.ssid ? nil : net.ssid
        } else {
            join(net, password: nil)
        }
    }

    /// Saved networks join through networksetup (stored credentials); new ones through
    /// CoreWLAN, so a typed password never reaches argv.
    func join(_ net: WiFiNetwork, password: String?) {
        guard let wifi else { return }
        connecting = net.ssid
        passwordFor = nil
        log.info("join start known=\(net.known, privacy: .public) password=\(password != nil, privacy: .public)")
        Task {
            do {
                if net.known && password == nil {
                    try await wifi.joinKnown(ssid: net.ssid)
                } else {
                    try await wifi.connect(ssid: net.ssid, password: password)
                }
                log.info("join ok")
            } catch {
                log.error("join failed: \(error.localizedDescription, privacy: .public)")
                joinError = (net.ssid, Self.friendly(error))
                if password != nil { passwordFor = net.ssid }
            }
            connecting = nil
            refreshNow(rescan: true)
        }
    }

    private static func friendly(_ error: Error) -> String {
        let code = (error as NSError).code
        if code == -3900 || code == -3924 { return "Incorrect password, or the network refused to join." }
        if code == -3905 { return "Network not found." }
        return error.localizedDescription
    }

    func setOpensAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            message = "Could not change Open at Login: \(error.localizedDescription)"
        }
        let status = SMAppService.mainApp.status
        opensAtLogin = status == .enabled
        if status == .requiresApproval {
            message = "Allow Mac Network in System Settings > General > Login Items."
        }
    }

    func quit() {
        NSApplication.shared.terminate(nil)
    }

    func openWiFiSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.wifi-settings-extension")!)
    }

    func forget(_ net: WiFiNetwork) {
        guard let wifi, net.canForget else { return }
        Task {
            do {
                try await wifi.forget(ssid: net.ssid)
                refreshNow(rescan: true)
            } catch let e as ShellError where e.message == "Cancelled" {
            } catch {
                message = "Could not forget \(net.ssid): \(error.localizedDescription)"
            }
        }
    }

    func lookUpPublicIP() {
        publicIP = .loading
        Task {
            do { publicIP = .value(try await PublicIP.lookup()) }
            catch { publicIP = .failed("Lookup failed") }
        }
    }
}

extension NetworkModel {
    static func preview(kind: ConnectionKind = .wifi, nameHidden: Bool = false) -> NetworkModel {
        let m = NetworkModel(live: false)
        m.kind = kind
        m.iface = kind == .wifi ? "en0" : "en7"
        m.address = "192.0.2.24/24"
        m.gateway = "192.0.2.1"
        m.link = kind == .wifi ? WiFiLink(ssid: nameHidden ? nil : "Harbor", signal: 78, rssi: -43, txRateMbps: 866, band: "5ghz", device: "en0") : nil
        m.ethernetMbps = kind == .ethernet ? 1000 : nil
        m.needsLocation = nameHidden
        m.networks = nameHidden ? [] : WiFiList.sorted([
            WiFiNetwork(ssid: "Harbor", signal: 78, connected: true, known: true, security: .personal),
            WiFiNetwork(ssid: "Office-5G", signal: 55, known: true, security: .enterprise),
            WiFiNetwork(ssid: "Cafe Guest", signal: 62, security: .open),
            WiFiNetwork(ssid: "Neighbour", signal: 30, security: .personal),
            WiFiNetwork(ssid: "Printer-Direct", signal: 45, security: .personal),
            WiFiNetwork(ssid: "Library", signal: 22, security: .owe),
        ])
        var t = Throughput().next(iface: "en0", rxBytes: 0, txBytes: 0, now: 1)
        t = t.next(iface: "en0", rxBytes: 2_400_000, txBytes: 310_000, now: 2)
        m.throughput = t
        var p = PingStats(window: 5, averageWindow: 20)
        for (r, i) in [(3.1, 14.0), (2.8, 15.2), (3.4, 13.9)] { p = p.next(iface: "en0", router: .ms(r), internet: .ms(i)) }
        m.ping = p
        return m
    }
}
