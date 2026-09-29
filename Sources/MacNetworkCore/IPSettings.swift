import Foundation

public struct NetworkService: Sendable, Equatable, Identifiable, Hashable {
    public let name: String    // "Wi-Fi", "USB 10/100/1000 LAN"
    public let device: String  // "en0"
    public var isWiFi: Bool { name == "Wi-Fi" }
    public var id: String { name }

    public init(name: String, device: String) {
        self.name = name
        self.device = device
    }
}

public enum IPMethod: Sendable, Equatable {
    case dhcp, manual
}

public struct IPConfig: Sendable, Equatable {
    public var service: String
    public var method: IPMethod
    public var address: String  // CIDR, "192.168.1.50/24"
    public var gateway: String
    public var dns: String      // comma-separated, empty = from DHCP

    public init(service: String, method: IPMethod, address: String = "", gateway: String = "", dns: String = "") {
        self.service = service
        self.method = method
        self.address = address
        self.gateway = gateway
        self.dns = dns
    }
}

/// IPv4 settings for Wi-Fi and Ethernet services, over `networksetup`.
/// Port of rohi.network `settings.py` (list / read / current / save).
public struct IPSettings: Sendable {
    static let networksetup = "/usr/sbin/networksetup"
    let run: Runner

    public init(run: @escaping Runner = Shell.run) {
        self.run = run
    }

    /// Enabled services backed by a real `en*` interface. Skips VPNs, bridges, disabled.
    public func services() async throws -> [NetworkService] {
        Self.parseServiceOrder(try await run(Self.networksetup, ["-listnetworkserviceorder"]))
    }

    /// The service carrying the default route, if any.
    public func activeService(in services: [NetworkService]) async -> NetworkService? {
        guard let out = try? await run("/sbin/route", ["-n", "get", "default"]),
              let line = out.split(separator: "\n").first(where: { $0.contains("interface:") }),
              let iface = line.split(separator: ":").last?.trimmingCharacters(in: .whitespaces)
        else { return nil }
        return services.first { $0.device == iface }
    }

    public func read(_ service: NetworkService) async throws -> IPConfig {
        let info = try await run(Self.networksetup, ["-getinfo", service.name])
        let dns = try await run(Self.networksetup, ["-getdnsservers", service.name])
        return Self.parseInfo(info, dns: dns, service: service.name)
    }

    /// Manual config pre-filled from the live DHCP lease, for "Use current IP as fixed".
    public func current(_ service: NetworkService) async throws -> IPConfig {
        var config = try await read(service)
        guard !config.address.isEmpty else {
            throw ShellError("Connect to this network first to use its current subnet")
        }
        if config.dns.isEmpty,
           let leased = try? await run("/usr/sbin/ipconfig", ["getoption", service.device, "domain_name_server"]) {
            config.dns = leased.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        config.method = .manual
        return config
    }

    public func save(_ config: IPConfig, services: [NetworkService]) async throws {
        let commands = try Self.commands(for: config, services: services)
        try await Shell.runAsAdmin(run, tool: Self.networksetup, commands: commands)
    }

    // MARK: Pure parts (tested)

    /// Validates like settings.py, then returns the `networksetup` argument lists to run.
    static func commands(for config: IPConfig, services: [NetworkService]) throws -> [[String]] {
        guard services.contains(where: { $0.name == config.service }) else {
            throw ShellError("Select a Wi-Fi or Ethernet connection")
        }
        let dns = config.dns.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard dns.allSatisfy(IPv4.isValid) else {
            throw ShellError("Use IPv4 DNS addresses separated by commas")
        }
        let dnsCommand = ["-setdnsservers", config.service] + (dns.isEmpty ? ["Empty"] : dns)

        switch config.method {
        case .dhcp:
            // DHCP clears the static address and router, so a stale one cannot block renewal.
            return [["-setdhcp", config.service], dnsCommand]
        case .manual:
            let address = config.address.trimmingCharacters(in: .whitespaces)
            guard !address.isEmpty else {
                throw ShellError("Enter an IPv4 address with prefix, such as 192.168.1.50/24")
            }
            guard !address.contains(",") else {
                throw ShellError("macOS allows one IPv4 address per service")
            }
            guard let cidr = IPv4.parseCIDR(address) else {
                throw ShellError("Use an IPv4 address with a prefix, such as 192.168.1.50/24")
            }
            let gateway = config.gateway.trimmingCharacters(in: .whitespaces)
            guard !gateway.isEmpty else {
                throw ShellError("Enter a gateway (router) address")  // networksetup -setmanual requires one
            }
            guard IPv4.isValid(gateway) else {
                throw ShellError("Gateway must be an IPv4 address")
            }
            return [["-setmanual", config.service, cidr.address, IPv4.mask(prefix: cidr.prefix), gateway], dnsCommand]
        }
    }

    /// Parses `-listnetworkserviceorder`:
    ///   (1) Wi-Fi
    ///   (Hardware Port: Wi-Fi, Device: en0)
    /// A disabled service shows as `(*) Name`.
    static func parseServiceOrder(_ out: String) -> [NetworkService] {
        var result: [NetworkService] = []
        var pending: String?
        for raw in out.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("(Hardware Port:") {
                guard let name = pending,
                      let device = line.components(separatedBy: "Device: ").last?.dropLast().description,
                      device.hasPrefix("en")
                else { pending = nil; continue }
                result.append(NetworkService(name: name, device: device))
                pending = nil
            } else if line.hasPrefix("("), let close = line.firstIndex(of: ")") {
                let tag = line[line.index(after: line.startIndex)..<close]
                pending = tag == "*" ? nil : String(line[line.index(after: close)...]).trimmingCharacters(in: .whitespaces)
            }
        }
        return result
    }

    /// Parses `-getinfo` + `-getdnsservers`.
    static func parseInfo(_ info: String, dns: String, service: String) -> IPConfig {
        var fields: [String: String] = [:]
        for line in info.split(separator: "\n") {
            let parts = line.split(separator: ":", maxSplits: 1)
            if parts.count == 2 { fields[String(parts[0])] = parts[1].trimmingCharacters(in: .whitespaces) }
        }
        let manual = info.hasPrefix("Manual")
        let ip = fields["IP address"].flatMap { IPv4.isValid($0) ? $0 : nil }
        let prefix = fields["Subnet mask"].flatMap(IPv4.prefix(mask:))
        let router = fields["Router"].flatMap { IPv4.isValid($0) ? $0 : nil }
        let servers = dns.split(separator: "\n").map(String.init).filter(IPv4.isValid)
        return IPConfig(
            service: service,
            method: manual ? .manual : .dhcp,
            address: ip.map { "\($0)/\(prefix ?? 24)" } ?? "",
            gateway: router ?? "",
            dns: servers.joined(separator: ",")
        )
    }
}
