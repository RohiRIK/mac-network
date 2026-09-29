import Foundation
import Testing
@testable import MacNetworkCore

// Validation cases ported from rohi.network test/settings.test.py.

let wifi = NetworkService(name: "Wi-Fi", device: "en0")

func commands(_ method: IPMethod, _ address: String = "", _ gateway: String = "", _ dns: String = "", service: String = "Wi-Fi") throws -> [[String]] {
    try IPSettings.commands(for: IPConfig(service: service, method: method, address: address, gateway: gateway, dns: dns), services: [wifi])
}

func rejects(_ message: String, _ body: () throws -> Any) {
    #expect(throws: ShellError.self) { _ = try body() }
    do { _ = try body() } catch { #expect(error.localizedDescription.contains(message), "\(error)") }
}

@Test func rejectsANonNetworkService() {
    rejects("Wi-Fi or Ethernet") { try commands(.dhcp, service: "VPN") }
}

@Test func rejectsManualWithNoAddress() {
    rejects("prefix") { try commands(.manual, "", "192.168.1.1") }
}

@Test func rejectsAddressWithoutPrefix() {
    rejects("prefix") { try commands(.manual, "192.168.1.50", "192.168.1.1") }
}

@Test func rejectsIPv6Address() {
    rejects("IPv4") { try commands(.manual, "2001:db8::1/64", "192.168.1.1") }
}

@Test func rejectsMalformedAddress() {
    rejects("IPv4") { try commands(.manual, "999.1.1.1/24", "192.168.1.1") }
    rejects("IPv4") { try commands(.manual, "192.168.1.50/33", "192.168.1.1") }
}

@Test func rejectsIPv6Gateway() {
    rejects("Gateway") { try commands(.manual, "192.168.1.50/24", "2001:db8::1") }
}

@Test func rejectsMalformedDNS() {
    rejects("DNS") { try commands(.manual, "192.168.1.50/24", "192.168.1.1", "not-an-ip") }
}

@Test func rejectsMultipleAddressesOnMacOS() {  // changed: networksetup allows one per service
    rejects("one IPv4 address") { try commands(.manual, "192.168.1.50/24,192.168.1.51/24", "192.168.1.1") }
}

@Test func requiresGatewayInManualOnMacOS() {  // changed: -setmanual needs a router
    rejects("gateway") { try commands(.manual, "192.168.1.50/24") }
}

@Test func acceptsValidManualConfig() throws {
    #expect(try commands(.manual, "192.168.1.50/24", "192.168.1.1", "1.1.1.1, 8.8.8.8") == [
        ["-setmanual", "Wi-Fi", "192.168.1.50", "255.255.255.0", "192.168.1.1"],
        ["-setdnsservers", "Wi-Fi", "1.1.1.1", "8.8.8.8"],
    ])
}

@Test func dhcpIgnoresStaticFieldsAndClearsDNSWhenEmpty() throws {
    #expect(try commands(.dhcp, "192.168.1.50/24", "192.168.1.1") == [
        ["-setdhcp", "Wi-Fi"],
        ["-setdnsservers", "Wi-Fi", "Empty"],
    ])
}

// MARK: Parsing real networksetup output (captured on macOS 26)

@Test func parsesServiceOrderSkippingBridgesVPNsAndDisabled() {
    let out = """
    An asterisk (*) denotes that a network service is disabled.
    (1) USB 10/100/1000 LAN
    (Hardware Port: USB 10/100/1000 LAN, Device: en7)

    (2) Thunderbolt Bridge
    (Hardware Port: Thunderbolt Bridge, Device: bridge0)

    (3) Wi-Fi
    (Hardware Port: Wi-Fi, Device: en0)

    (*) iPhone USB
    (Hardware Port: iPhone USB, Device: en8)

    (4) VPN
    (Hardware Port: com.example.vpn, Device: )
    """
    #expect(IPSettings.parseServiceOrder(out) == [
        NetworkService(name: "USB 10/100/1000 LAN", device: "en7"),
        NetworkService(name: "Wi-Fi", device: "en0"),
    ])
}

@Test func parsesDHCPInfo() {
    let info = """
    DHCP Configuration
    IP address: 192.0.2.24
    Subnet mask: 255.255.255.0
    Router: 192.0.2.1
    Client ID:
    IPv6: Off
    Wi-Fi ID: 00:00:5e:00:53:01
    """
    let c = IPSettings.parseInfo(info, dns: "There aren't any DNS Servers set on Wi-Fi.", service: "Wi-Fi")
    #expect(c == IPConfig(service: "Wi-Fi", method: .dhcp, address: "192.0.2.24/24", gateway: "192.0.2.1", dns: ""))
}

@Test func parsesManualInfoWithDNS() {
    let info = "Manual Configuration\nIP address: 192.168.1.50\nSubnet mask: 255.255.254.0\nRouter: 192.168.1.1\n"
    let c = IPSettings.parseInfo(info, dns: "1.1.1.1\n8.8.8.8\n", service: "Wi-Fi")
    #expect(c.method == .manual)
    #expect(c.address == "192.168.1.50/23")
    #expect(c.dns == "1.1.1.1,8.8.8.8")
}

@Test func parsesDisconnectedInfoAsEmpty() {
    let c = IPSettings.parseInfo("DHCP Configuration\nIP address: none\nRouter: none\n", dns: "", service: "Wi-Fi")
    #expect(c.address.isEmpty && c.gateway.isEmpty)
}

@Test func currentRefusesWhenNotConnected() async {
    let settings = IPSettings { _, args in args.first == "-getinfo" ? "DHCP Configuration\n" : "" }
    await #expect(throws: ShellError.self) { try await settings.current(wifi) }
}

@Test func currentFillsDNSFromLease() async throws {
    let settings = IPSettings { tool, args in
        if tool.hasSuffix("ipconfig") { return "192.0.2.1\n" }
        if args.first == "-getinfo" { return "DHCP Configuration\nIP address: 192.0.2.24\nSubnet mask: 255.255.255.0\nRouter: 192.0.2.1\n" }
        return "There aren't any DNS Servers set on Wi-Fi."
    }
    let c = try await settings.current(wifi)
    #expect(c == IPConfig(service: "Wi-Fi", method: .manual, address: "192.0.2.24/24", gateway: "192.0.2.1", dns: "192.0.2.1"))
}

// MARK: IPv4

@Test func maskAndPrefixRoundTrip() {
    #expect(IPv4.mask(prefix: 24) == "255.255.255.0")
    #expect(IPv4.mask(prefix: 0) == "0.0.0.0")
    #expect(IPv4.mask(prefix: 32) == "255.255.255.255")
    #expect(IPv4.prefix(mask: "255.255.254.0") == 23)
    #expect(IPv4.prefix(mask: "255.0.255.0") == nil)
}

// MARK: Admin command quoting (security)

@Test func osascriptQuotingBlocksInjection() async throws {
    // Same script as the admin path, minus the password prompt, with printf as the tool
    // so every argument comes back verbatim, one per line.
    let hostile = ["-setmanual", "Wi-Fi'; touch /tmp/pwned-mac-network; '", "$(id)", "a\"b\\c", "&& id"]
    let args = Shell.osascriptArgs(tool: "/usr/bin/printf", commands: [["%s\\n"] + hostile, ["%s\\n", "second"]], admin: false)
    let out = try await Shell.run("/usr/bin/osascript", args)
    #expect(out.split(whereSeparator: \.isNewline).map(String.init) == hostile + ["second"])  // do shell script turns \n into \r
    #expect(!FileManager.default.fileExists(atPath: "/tmp/pwned-mac-network"))
}

// MARK: Public IP (ported)

@Test func publicIPValidatesTheAddress() throws {
    #expect(try PublicIP.parse(Data(#"{"ip":"203.0.113.7"}"#.utf8)) == "203.0.113.7")
}

@Test func publicIPRejectsNonIPv4Payload() {
    #expect(throws: ShellError.self) { try PublicIP.parse(Data(#"{"ip":"2001:db8::1"}"#.utf8)) }
    #expect(throws: ShellError.self) { try PublicIP.parse(Data("<html>".utf8)) }
}

// MARK: Live, read-only (this Mac / CI runner)

@Test func readsLiveServices() async throws {
    let settings = IPSettings()
    let services = try await settings.services()
    #expect(!services.isEmpty)
    let config = try await settings.read(services[0])
    #expect(config.service == services[0].name)
}

// MARK: Shell timeout

@Test func shellKillsHungToolAfterTimeout() async {
    let start = Date()
    await #expect(throws: ShellError("sleep timed out")) {
        _ = try await Shell.runner(timeout: 1)("/bin/sleep", ["10"])
    }
    #expect(Date().timeIntervalSince(start) < 5)
}

@Test func shellReturnsOutputBeforeTimeout() async throws {
    #expect(try await Shell.runner(timeout: 5)("/bin/echo", ["ok"]) == "ok\n")
}
