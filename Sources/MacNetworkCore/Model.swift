import Foundation

/// Pure formatting helpers ported from rohi.network `Model.js`. Same inputs, same strings.
public enum Model {
    public static func formatBytes(_ bytes: Double) -> String {
        let n = bytes.isFinite && bytes >= 0 ? bytes : 0
        let kb = 1024.0, mb = kb * 1024, gb = mb * 1024
        if n < kb { return "\(Int(n.rounded())) B" }
        if n < mb { return fixed(n / kb, 1) + " KB" }
        if n < gb { return fixed(n / mb, 1) + " MB" }
        return fixed(n / gb, 2) + " GB"
    }

    public static func formatRate(_ bytesPerSec: Double) -> String {
        formatBytes(bytesPerSec) + "/s"
    }

    /// Ethernet negotiated link speed, e.g. 1000 -> "1gbit".
    public static func formatHeaderSpeed(_ mbps: Int?) -> String {
        guard let v = mbps, v > 0 else { return "" }
        if v >= 1000 { return fixed(Double(v) / 1000, v % 1000 == 0 ? 0 : 1) + "gbit" }
        return "\(v)mbit"
    }

    public static func formatHeaderFreq(_ mhz: Double) -> String {
        guard mhz > 0 else { return "" }
        switch mhz {
        case 2400..<2500: return "2.4ghz"
        case 4900..<5925: return "5ghz"
        case 5925..<7125: return "6ghz"
        case 57000..<71000: return "60ghz"
        default:
            let ghz = mhz / 1000
            return fixed(ghz, ghz.truncatingRemainder(dividingBy: 1) == 0 ? 0 : 1) + "ghz"
        }
    }

    /// `nil` latency means the probe timed out. `hasSamples` false means no probe
    /// has returned yet, so the row reads "--" instead of reflowing later.
    public static func formatPingLatency(_ ms: Double?, hasSamples: Bool) -> String {
        guard hasSamples else { return "--" }
        guard let v = ms, v.isFinite, v >= 0 else { return "Timeout" }
        return fixed(v, v > 0 && v < 10 ? 1 : 0) + " ms"
    }

    public static func formatPacketLoss(_ percent: Int, hasSamples: Bool) -> String {
        guard hasSamples else { return "--" }
        return "\(max(0, percent))%"
    }

    /// Matches JS `toFixed`: halves round away from zero. `String(format:)` rounds
    /// exact halves to even (4.25 -> "4.2"), which would break parity with the source.
    static func fixed(_ value: Double, _ digits: Int) -> String {
        let scale = pow(10, Double(digits))
        let rounded = (value * scale).rounded(.toNearestOrAwayFromZero) / scale
        return String(format: "%.\(digits)f", rounded)
    }
}
