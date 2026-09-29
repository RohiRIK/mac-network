import Darwin
import Foundation

/// One interface's live IPv4 address and byte counters, from `getifaddrs`.
public struct InterfaceSample: Sendable, Equatable {
    public var address: String?  // "192.0.2.24/24"
    public var rxBytes: Double
    public var txBytes: Double
}

/// Live link data the panel polls: default route, addresses, counters, ping, Ethernet speed.
public struct LinkProbe: Sendable {
    let run: Runner

    public init(run: @escaping Runner = Shell.run) {
        self.run = run
    }

    /// Interface and gateway of the default route, nil when offline.
    public func defaultRoute() async -> (iface: String, gateway: String?)? {
        guard let out = try? await run("/sbin/route", ["-n", "get", "default"]) else { return nil }
        return Self.parseRoute(out)
    }

    /// `.lost` on timeout or error. One probe, 1 s timeout.
    public func ping(_ host: String) async -> Probe {
        guard let out = try? await run("/sbin/ping", ["-n", "-c", "1", "-t", "1", host]),
              let ms = Self.parsePingTime(out) else { return .lost }
        return .ms(ms)
    }

    /// Negotiated Ethernet speed in Mbit/s from `ifconfig` media line, nil for Wi-Fi/unknown.
    public func ethernetSpeed(_ iface: String) async -> Int? {
        guard let out = try? await run("/sbin/ifconfig", [iface]) else { return nil }
        return Self.parseMediaSpeed(out)
    }

    public static func sample(_ iface: String) -> InterfaceSample {
        var result = InterfaceSample(address: nil, rxBytes: 0, txBytes: 0)
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0 else { return result }
        defer { freeifaddrs(head) }

        for ptr in sequence(first: head, next: { $0?.pointee.ifa_next }).compactMap({ $0 }) {
            let entry = ptr.pointee
            guard String(cString: entry.ifa_name) == iface, let addr = entry.ifa_addr else { continue }
            switch Int32(addr.pointee.sa_family) {
            case AF_INET:
                let ip = ntop(addr)
                let prefix = entry.ifa_netmask.flatMap { IPv4.prefix(mask: ntop($0)) }
                result.address = prefix.map { "\(ip)/\($0)" } ?? ip
            case AF_LINK:
                // ponytail: if_data counters are 32-bit and wrap at 4 GiB; Throughput clamps
                // the wrap to one zero-rate sample. Use sysctl IFMIB_IFDATA 64-bit if it matters.
                if let data = entry.ifa_data?.assumingMemoryBound(to: if_data.self).pointee {
                    result.rxBytes = Double(data.ifi_ibytes)
                    result.txBytes = Double(data.ifi_obytes)
                }
            default:
                continue
            }
        }
        return result
    }

    private static func ntop(_ sa: UnsafeMutablePointer<sockaddr>) -> String {
        var sin = sa.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr }
        var buf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        inet_ntop(AF_INET, &sin, &buf, socklen_t(INET_ADDRSTRLEN))
        return String(decoding: buf.prefix { $0 != 0 }.map(UInt8.init), as: UTF8.self)
    }

    // MARK: Pure (tested)

    static func parseRoute(_ out: String) -> (iface: String, gateway: String?)? {
        var fields: [String: String] = [:]
        for line in out.split(separator: "\n") {
            let parts = line.split(separator: ":", maxSplits: 1)
            if parts.count == 2 {
                fields[parts[0].trimmingCharacters(in: .whitespaces)] = parts[1].trimmingCharacters(in: .whitespaces)
            }
        }
        guard let iface = fields["interface"], !iface.isEmpty else { return nil }
        return (iface, fields["gateway"].flatMap { IPv4.isValid($0) ? $0 : nil })
    }

    static func parsePingTime(_ out: String) -> Double? {
        guard let range = out.range(of: #"time=([0-9.]+) ms"#, options: .regularExpression) else { return nil }
        return Double(out[range].dropFirst(5).dropLast(3))
    }

    /// "media: autoselect (1000baseT <full-duplex>)" -> 1000; "(2.5GbaseT" -> 2500.
    static func parseMediaSpeed(_ out: String) -> Int? {
        guard let range = out.range(of: #"\(([0-9.]+)(G?)base"#, options: .regularExpression) else { return nil }
        let token = out[range].dropFirst().dropLast(4)
        let giga = token.hasSuffix("G")
        guard let value = Double(giga ? token.dropLast() : token) else { return nil }
        return Int(giga ? value * 1000 : value)
    }
}
