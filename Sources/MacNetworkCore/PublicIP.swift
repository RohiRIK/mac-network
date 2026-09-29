import Foundation

/// Public IPv4 via ipify.org. Contacts a third party, so callers run it only on click.
public enum PublicIP {
    static let url = URL(string: "https://api.ipify.org?format=json")!

    public static func lookup(session: URLSession = .shared) async throws -> String {
        var request = URLRequest(url: url, timeoutInterval: 8)
        request.setValue("mac-network", forHTTPHeaderField: "User-Agent")
        let (data, _) = try await session.data(for: request)
        return try parse(data)
    }

    static func parse(_ data: Data) throws -> String {
        struct Payload: Decodable { let ip: String }
        guard data.count <= 1024,
              let ip = try? JSONDecoder().decode(Payload.self, from: data).ip,
              IPv4.isValid(ip)
        else { throw ShellError("Public IP lookup returned an unexpected answer") }
        return ip
    }
}
