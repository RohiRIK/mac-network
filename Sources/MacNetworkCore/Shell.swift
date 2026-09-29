import Foundation

public struct ShellError: LocalizedError, Equatable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

/// Runs a tool and returns stdout. `@Sendable` so services can hold it and tests can fake it.
public typealias Runner = @Sendable (_ tool: String, _ args: [String]) async throws -> String

public enum Shell {
    /// Off the main thread; never blocks the menu. Killed after 20 s.
    public static let run: Runner = runner(timeout: 20)

    /// A runner that terminates the tool after `timeout` seconds and throws "timed out".
    public static func runner(timeout: Double) -> Runner {
        { tool, args in try await execute(tool, args, timeout: timeout) }
    }

    // GCD, not Swift concurrency: Process and pipe reads are blocking synchronous APIs.
    private static func execute(_ tool: String, _ args: [String], timeout: Double) async throws -> String {
        try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global().async {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: tool)
                p.arguments = args
                let out = Pipe(), err = Pipe()
                p.standardOutput = out
                p.standardError = err
                do { try p.run() } catch { return cont.resume(throwing: error) }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                    if p.isRunning { p.terminate() }
                }
                // ponytail: reads stdout then stderr; a tool flooding stderr past the pipe
                // buffer would stall. Fine for networksetup/osascript output sizes.
                let o = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                let e = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                p.waitUntilExit()
                if p.terminationReason == .uncaughtSignal {
                    return cont.resume(throwing: ShellError("\((tool as NSString).lastPathComponent) timed out"))
                }
                if p.terminationStatus == 0 { return cont.resume(returning: o) }
                let detail = (e + o).trimmingCharacters(in: .whitespacesAndNewlines)
                cont.resume(throwing: ShellError(detail.isEmpty ? "\(tool) failed" : detail))
            }
        }
    }

    /// AppleScript that runs `tool` once per command group, joined with `&&`, with every
    /// argument passed through `quoted form of`. Arguments travel as argv, never spliced
    /// into script source, so a hostile service name cannot inject shell or AppleScript.
    static func script(tool: String, admin: Bool) -> [String] {
        [
            "on run argv",
            "set cmd to \(appleScriptString(tool))",
            "repeat with a in argv",
            "if (a as text) is \"\(separator)\" then",
            "set cmd to cmd & \" && \" & \(appleScriptString(tool))",
            "else",
            "set cmd to cmd & \" \" & quoted form of (a as text)",
            "end if",
            "end repeat",
            "do shell script cmd" + (admin ? " with administrator privileges" : ""),
            "end run",
        ]
    }

    static let separator = "&&"

    static func appleScriptString(_ s: String) -> String {
        "quoted form of \"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    /// osascript argv for `commands` (each an arg list for `tool`).
    static func osascriptArgs(tool: String, commands: [[String]], admin: Bool) -> [String] {
        // "--" ends osascript's own flags; without it "-setmanual" is read as `-s etmanual`.
        script(tool: tool, admin: admin).flatMap { ["-e", $0] } + ["--"]
            + Array(commands.joined(separator: [separator]))
    }

    /// Runs `commands` as root behind one macOS password prompt.
    public static func runAsAdmin(_ run: @escaping Runner = Shell.run, tool: String, commands: [[String]]) async throws {
        do {
            _ = try await run("/usr/bin/osascript", osascriptArgs(tool: tool, commands: commands, admin: true))
        } catch let e as ShellError where e.message.contains("-128") {
            throw ShellError("Cancelled")
        }
    }
}
