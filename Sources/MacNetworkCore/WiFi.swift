import Foundation

public enum ConnectionKind: Sendable {
    case wifi, ethernet, disconnected

    /// SF Symbol for the menu bar and header. Wi-Fi strength goes through
    /// `Image(systemName:variableValue:)` with `signal / 100`.
    public var symbolName: String {
        switch self {
        case .wifi: "wifi"
        case .ethernet: "cable.connector"
        case .disconnected: "wifi.slash"
        }
    }
}

public enum WiFiSecurity: Sendable {
    case open, owe, personal, enterprise, unknown

    /// OWE (Enhanced Open) encrypts without authenticating, so like open it has
    /// nothing to ask for. Unknown stays credentialed as the conservative fallback.
    public var requiresCredentials: Bool {
        self != .open && self != .owe
    }
}

public struct WiFiNetwork: Sendable, Equatable, Identifiable {
    public var ssid: String
    public var signal: Int  // 0...100
    public var connected: Bool
    public var known: Bool
    public var security: WiFiSecurity

    public var id: String { ssid }

    public init(ssid: String, signal: Int, connected: Bool = false, known: Bool = false, security: WiFiSecurity = .unknown) {
        self.ssid = ssid
        self.signal = signal
        self.connected = connected
        self.known = known
        self.security = security
    }

    public var canForget: Bool { known && !connected }
}

public enum WiFiList {
    /// Connected first, then known, then strongest.
    public static func sorted(_ rows: [WiFiNetwork]) -> [WiFiNetwork] {
        rows.sorted { a, b in
            if a.connected != b.connected { return a.connected }
            if a.known != b.known { return a.known }
            return a.signal > b.signal
        }
    }

    /// Header shown above row `index` of a sorted list, or nil.
    public static func sectionTitle(_ rows: [WiFiNetwork], at index: Int) -> String? {
        guard rows.indices.contains(index) else { return nil }
        let net = rows[index]
        if net.known { return index == 0 ? "Known networks" : nil }
        if index == 0 || rows[index - 1].known { return "Other networks" }
        return nil
    }
}
