import Testing
@testable import MacNetworkCore

@Test func parsesDefaultRoute() {
    let out = """
       route to: default
    destination: default
           mask: default
        gateway: 192.0.2.1
      interface: en0
          flags: <UP,GATEWAY,DONE,STATIC,PRCLONING,GLOBAL>
    """
    let r = LinkProbe.parseRoute(out)
    #expect(r?.iface == "en0")
    #expect(r?.gateway == "192.0.2.1")
}

@Test func routeWithoutInterfaceIsOffline() {
    #expect(LinkProbe.parseRoute("route: writing to routing socket: not in table") == nil)
}

@Test func parsesPingTime() {
    let out = "PING 1.1.1.1 (1.1.1.1): 56 data bytes\n64 bytes from 1.1.1.1: icmp_seq=0 ttl=57 time=12.345 ms\n"
    #expect(LinkProbe.parsePingTime(out) == 12.345)
    #expect(LinkProbe.parsePingTime("Request timeout for icmp_seq 0") == nil)
}

@Test func parsesEthernetMediaSpeed() {
    #expect(LinkProbe.parseMediaSpeed("\tmedia: autoselect (1000baseT <full-duplex>)") == 1000)
    #expect(LinkProbe.parseMediaSpeed("\tmedia: autoselect (2.5GbaseT <full-duplex>)") == 2500)
    #expect(LinkProbe.parseMediaSpeed("\tmedia: autoselect\n\tstatus: active") == nil)
}

@Test func samplesLoopbackLive() {
    let s = LinkProbe.sample("lo0")
    #expect(s.address == "127.0.0.1/8")
    #expect(s.rxBytes > 0)
}

/// Live ping is machine-dependent (firewall stealth mode drops loopback ICMP), so fake the tool.
@Test func pingMapsOutputAndFailure() async {
    let ok = LinkProbe { _, _ in "64 bytes from 10.0.0.1: icmp_seq=0 ttl=64 time=6.000 ms\n" }
    #expect(await ok.ping("10.0.0.1") == .ms(6))
    let down = LinkProbe { _, _ in throw ShellError("timeout") }
    #expect(await down.ping("10.0.0.1") == .lost)
}
