import Foundation

/// Byte counters -> rates. Resets when the interface changes.
public struct Throughput: Sendable, Equatable {
    public var iface = ""
    public var rxBytes = 0.0
    public var txBytes = 0.0
    public var sampleTime = 0.0
    public var downloadRate = 0.0
    public var uploadRate = 0.0

    public init() {}

    public func next(iface: String, rxBytes: Double, txBytes: Double, now: Double) -> Throughput {
        var out = Throughput()
        out.iface = iface
        out.rxBytes = rxBytes
        out.txBytes = txBytes
        out.sampleTime = now
        guard iface == self.iface, sampleTime != 0 else { return out }

        out.downloadRate = downloadRate
        out.uploadRate = uploadRate
        let dt = now - sampleTime
        if dt > 0 {
            out.downloadRate = max(0, (rxBytes - self.rxBytes) / dt)
            out.uploadRate = max(0, (txBytes - self.txBytes) / dt)
        }
        return out
    }
}

/// One ping result. `.lost` counts toward packet loss.
public enum Probe: Sendable, Equatable {
    case ms(Double)
    case lost
}

/// Rolling ping windows for the router and an internet host.
/// Samples are `nil` for a lost probe.
public struct PingStats: Sendable, Equatable {
    public var iface = ""
    public var router: [Double?] = []
    public var internet: [Double?] = []
    public var window = 5
    public var averageWindow = 5

    public init(window: Int = 5, averageWindow: Int? = nil) {
        self.window = max(1, window)
        self.averageWindow = max(1, averageWindow ?? window)
    }

    /// A `nil` probe means that target was not measured this round (no router),
    /// which clears its window, as in the source.
    public func next(iface: String, router routerProbe: Probe?, internet internetProbe: Probe?) -> PingStats {
        let reset = iface.isEmpty || iface != self.iface
        var out = self
        out.iface = iface
        out.router = routerProbe.map { Self.append(reset ? [] : router, $0, limit: window) } ?? []
        out.internet = internetProbe.map { Self.append(reset ? [] : internet, $0, limit: window) } ?? []
        return out
    }

    public var routerLatency: Double? { Self.average(router, limit: averageWindow) }
    public var internetLatency: Double? { Self.average(internet, limit: averageWindow) }
    public var internetPacketLoss: Int { Self.packetLoss(internet) }

    static func append(_ samples: [Double?], _ probe: Probe, limit: Int) -> [Double?] {
        let value: Double? = if case .ms(let v) = probe, v.isFinite, v >= 0 { v } else { nil }
        return Array((samples + [value]).suffix(limit))
    }

    /// Mean of the successful samples in the last `limit`, or nil when none succeeded.
    static func average(_ samples: [Double?], limit: Int) -> Double? {
        let hits = samples.suffix(max(1, limit)).compactMap { $0 }
        return hits.isEmpty ? nil : hits.reduce(0, +) / Double(hits.count)
    }

    static func packetLoss(_ samples: [Double?]) -> Int {
        guard !samples.isEmpty else { return 0 }
        let lost = samples.filter { $0 == nil }.count
        return Int((Double(lost) / Double(samples.count) * 100).rounded())
    }
}
