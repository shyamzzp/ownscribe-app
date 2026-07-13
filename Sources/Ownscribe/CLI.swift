import Foundation

/// Locates the installed ownscribe CLI and runs subcommands.
/// GUI apps do not inherit the shell PATH, so we resolve the binary explicitly.
enum CLI {
    static var binaryURL: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        // Preferred: uv tool install location.
        let candidates = [
            home.appendingPathComponent(".local/bin/ownscribe"),
            URL(fileURLWithPath: "/opt/homebrew/bin/ownscribe"),
            URL(fileURLWithPath: "/usr/local/bin/ownscribe"),
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
            ?? candidates[0]
    }

    static var isInstalled: Bool {
        FileManager.default.isExecutableFile(atPath: binaryURL.path)
    }

    static var outputDir: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("ownscribe")
    }

    static var configPath: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/ownscribe/config.toml")
    }

    /// Build a process for a subcommand. Caller owns launch/termination.
    static func process(_ args: [String]) -> Process {
        let p = Process()
        p.executableURL = binaryURL
        p.arguments = args
        var env = ProcessInfo.processInfo.environment
        // Ensure ffmpeg etc. on PATH for the child even under a GUI launch.
        let extra = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        env["PATH"] = (env["PATH"].map { "\($0):\(extra)" }) ?? extra
        p.environment = env
        return p
    }

    /// Run a subcommand to completion, returning combined stdout+stderr.
    @discardableResult
    static func runBlocking(_ args: [String]) -> (status: Int32, output: String) {
        let p = process(args)
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        do {
            try p.run()
        } catch {
            return (-1, "Failed to launch ownscribe: \(error.localizedDescription)")
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }
}
