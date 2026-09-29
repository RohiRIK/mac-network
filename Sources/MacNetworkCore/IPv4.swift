import Darwin

/// Strict dotted-quad IPv4 helpers (inet_pton rejects 999.1.1.1, IPv6, hostnames).
public enum IPv4 {
    public static func isValid(_ s: String) -> Bool {
        var addr = in_addr()
        return inet_pton(AF_INET, s, &addr) == 1
    }

    /// "192.168.1.50/24" -> ("192.168.1.50", 24), nil if not IPv4 with a 0...32 prefix.
    public static func parseCIDR(_ s: String) -> (address: String, prefix: Int)? {
        let parts = s.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2, isValid(String(parts[0])),
              let prefix = Int(parts[1]), (0...32).contains(prefix) else { return nil }
        return (String(parts[0]), prefix)
    }

    public static func mask(prefix: Int) -> String {
        let bits: UInt32 = prefix == 0 ? 0 : ~UInt32(0) << (32 - prefix)
        return [24, 16, 8, 0].map { String((bits >> UInt32($0)) & 0xff) }.joined(separator: ".")
    }

    /// "255.255.255.0" -> 24, nil for a non-contiguous or invalid mask.
    public static func prefix(mask: String) -> Int? {
        guard isValid(mask) else { return nil }
        let octets = mask.split(separator: ".").compactMap { UInt32($0) }
        let bits = octets.reduce(UInt32(0)) { $0 << 8 | $1 }
        let ones = bits.nonzeroBitCount
        return self.mask(prefix: ones) == mask ? ones : nil
    }
}
