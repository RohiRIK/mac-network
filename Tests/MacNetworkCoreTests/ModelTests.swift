import AppKit
import Testing
@testable import MacNetworkCore

// Cases ported from rohi.network test/model.test.js unless marked "new".

@Test func formatBytesScalesThroughTheUnits() {
    #expect(Model.formatBytes(512) == "512 B")
    #expect(Model.formatBytes(2048) == "2.0 KB")
    #expect(Model.formatBytes(1024 * 1024 * 1024) == "1.00 GB")
}

@Test func formatBytesClampsNegativeToZero() {
    #expect(Model.formatBytes(-5) == "0 B")
}

@Test func formatRateAppendsPerSecondSuffix() {
    #expect(Model.formatRate(1024) == "1.0 KB/s")
}

@Test func formatHeaderSpeedConvertsMbitToGbit() {
    #expect(Model.formatHeaderSpeed(1000) == "1gbit")
    #expect(Model.formatHeaderSpeed(2500) == "2.5gbit")  // new
    #expect(Model.formatHeaderSpeed(150) == "150mbit")
}

@Test func formatHeaderSpeedIsEmptyForMissingValue() {
    #expect(Model.formatHeaderSpeed(0) == "")
    #expect(Model.formatHeaderSpeed(nil) == "")
}

@Test func formatHeaderFreqNamesTheBands() {  // new: source only checked non-empty
    #expect(Model.formatHeaderFreq(2437) == "2.4ghz")
    #expect(Model.formatHeaderFreq(5200) == "5ghz")
    #expect(Model.formatHeaderFreq(6115) == "6ghz")
    #expect(Model.formatHeaderFreq(0) == "")
}

@Test func formatPingLatencyReadsTimeoutForLostProbe() {
    #expect(Model.formatPingLatency(nil, hasSamples: true) == "Timeout")
    #expect(Model.formatPingLatency(-1, hasSamples: true) == "Timeout")
}

@Test func formatPingLatencyShowsOneDecimalBelow10ms() {
    #expect(Model.formatPingLatency(4.25, hasSamples: true) == "4.3 ms")
    #expect(Model.formatPingLatency(42, hasSamples: true) == "42 ms")
}

@Test func formatPingLatencyShowsDashesBeforeFirstProbe() {
    #expect(Model.formatPingLatency(20, hasSamples: false) == "--")
}

@Test func formatPacketLossDistinguishesNoSamplesFromZero() {
    #expect(Model.formatPacketLoss(25, hasSamples: true) == "25%")
    #expect(Model.formatPacketLoss(0, hasSamples: true) == "0%")
    #expect(Model.formatPacketLoss(25, hasSamples: false) == "--")
}

// MARK: Wi-Fi list

@Test func sortPutsConnectedFirstThenKnownThenStrongest() {
    let rows = [
        WiFiNetwork(ssid: "open-strong", signal: 95),
        WiFiNetwork(ssid: "known-weak", signal: 20, known: true),
        WiFiNetwork(ssid: "connected-any", signal: 10, connected: true),
    ]
    #expect(WiFiList.sorted(rows).map(\.ssid) == ["connected-any", "known-weak", "open-strong"])
}

@Test func sectionTitleOpensKnownBlock() {
    let nets = [true, true, false].map { WiFiNetwork(ssid: "\($0)", signal: 0, known: $0) }
    #expect(WiFiList.sectionTitle(nets, at: 0) == "Known networks")
    #expect(WiFiList.sectionTitle(nets, at: 1) == nil)
}

@Test func sectionTitleOpensOtherBlockAtTransition() {
    let nets = [true, false, false].map { WiFiNetwork(ssid: "\($0)", signal: 0, known: $0) }
    #expect(WiFiList.sectionTitle(nets, at: 1) == "Other networks")
    #expect(WiFiList.sectionTitle(nets, at: 2) == nil)
}

@Test func sectionTitleIsNilOutOfRange() {
    #expect(WiFiList.sectionTitle([WiFiNetwork(ssid: "a", signal: 0, known: true)], at: 5) == nil)
    #expect(WiFiList.sectionTitle([], at: 0) == nil)
}

@Test func onlyOpenAndOweSkipCredentials() {
    #expect(WiFiSecurity.personal.requiresCredentials)
    #expect(WiFiSecurity.enterprise.requiresCredentials)
    #expect(WiFiSecurity.unknown.requiresCredentials)
    #expect(!WiFiSecurity.open.requiresCredentials)
    #expect(!WiFiSecurity.owe.requiresCredentials)
}

@Test func canForgetOnlyKnownDisconnected() {
    #expect(WiFiNetwork(ssid: "a", signal: 0, connected: false, known: true).canForget)
    #expect(!WiFiNetwork(ssid: "a", signal: 0, connected: true, known: true).canForget)
    #expect(!WiFiNetwork(ssid: "a", signal: 0, connected: false, known: false).canForget)
}

@Test func connectionSymbolsExistInSFSymbols() {  // new: a wrong name renders nothing
    for kind in [ConnectionKind.wifi, .ethernet, .disconnected] {
        #expect(NSImage(systemSymbolName: kind.symbolName, accessibilityDescription: nil) != nil, "\(kind.symbolName)")
    }
}

// MARK: Throughput (new)

@Test func throughputFirstSampleHasZeroRate() {
    let t = Throughput().next(iface: "en0", rxBytes: 1000, txBytes: 500, now: 10)
    #expect(t.downloadRate == 0 && t.uploadRate == 0)
}

@Test func throughputComputesBytesPerSecond() {
    let t = Throughput()
        .next(iface: "en0", rxBytes: 1000, txBytes: 500, now: 10)
        .next(iface: "en0", rxBytes: 3000, txBytes: 1500, now: 12)
    #expect(t.downloadRate == 1000)
    #expect(t.uploadRate == 500)
}

@Test func throughputResetsOnInterfaceChange() {
    let t = Throughput()
        .next(iface: "en0", rxBytes: 1000, txBytes: 0, now: 10)
        .next(iface: "en1", rxBytes: 9000, txBytes: 0, now: 12)
    #expect(t.downloadRate == 0)
}

@Test func throughputNeverNegativeAfterCounterReset() {
    let t = Throughput()
        .next(iface: "en0", rxBytes: 5000, txBytes: 0, now: 10)
        .next(iface: "en0", rxBytes: 100, txBytes: 0, now: 11)
    #expect(t.downloadRate == 0)
}

// MARK: Ping

@Test func packetLossCountsLostSamples() {
    #expect(PingStats.packetLoss([1, nil, nil, 1]) == 50)
    #expect(PingStats.packetLoss([1, 1]) == 0)
    #expect(PingStats.packetLoss([]) == 0)
}

@Test func pingStatsStartEmpty() {
    let s = PingStats(window: 5, averageWindow: 20)
    #expect(s.routerLatency == nil && s.internetLatency == nil && s.internetPacketLoss == 0)
}

@Test func pingStatsKeepsRollingWindow() {  // new
    var s = PingStats(window: 3)
    for ms in [10.0, 20, 30, 40] { s = s.next(iface: "en0", router: .ms(ms), internet: .ms(ms)) }
    #expect(s.internet == [20, 30, 40])
    #expect(s.internetLatency == 30)
}

@Test func pingStatsLatencyIgnoresLostAndLossCountsThem() {  // new
    var s = PingStats(window: 4)
    for p in [Probe.ms(10), .lost, .ms(30), .lost] { s = s.next(iface: "en0", router: nil, internet: p) }
    #expect(s.internetLatency == 20)
    #expect(s.internetPacketLoss == 50)
    #expect(s.router.isEmpty)
}

@Test func pingStatsResetOnInterfaceChange() {  // new
    let s = PingStats()
        .next(iface: "en0", router: .ms(5), internet: .lost)
        .next(iface: "en1", router: .ms(7), internet: .ms(9))
    #expect(s.router == [7])
    #expect(s.internetPacketLoss == 0)
}

// MARK: Wi-Fi signal (new)

@Test func signalPercentMapsRSSIRange() {
    #expect(WiFiService.signalPercent(rssi: -95) == 0)
    #expect(WiFiService.signalPercent(rssi: -90) == 0)
    #expect(WiFiService.signalPercent(rssi: -60) == 50)
    #expect(WiFiService.signalPercent(rssi: -30) == 100)
    #expect(WiFiService.signalPercent(rssi: -20) == 100)
}

@Test func joinFailureReadsNetworksetupStdout() {  // networksetup exits 0 on failure
    #expect(WiFiService.joinFailure("") == nil)
    #expect(WiFiService.joinFailure("Could not find network Harbor.") != nil)
    #expect(WiFiService.joinFailure("Failed to join network Harbor.\nError: -3900  The operation couldn't be completed.") != nil)
}
