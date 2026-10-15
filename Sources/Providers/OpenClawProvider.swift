import Foundation
import os

/// How full the local OpenClaw agent's context is.
///
/// OpenClaw's gateway speaks an authenticated WebSocket protocol rather than a
/// plain status endpoint, so the session list is read the way a person would:
/// `openclaw sessions list --json`, with a timeout, on the store's cadence. The
/// CLI only reads OpenClaw's own session database; nothing is sent to the agent.
actor OpenClawProvider: UsageProvider {
    nonisolated let id = "openclaw"
    nonisolated let displayName = "OpenClaw"
    nonisolated let glyph = ProviderGlyph.openclaw

    static let candidatePaths = ["/opt/homebrew/bin/openclaw", "/usr/local/bin/openclaw"]

    private let executable: () -> String?
    private let timeout: TimeInterval
    private let minimumInterval: TimeInterval
    private var cached: (at: Date, key: String?, snapshot: ProviderSnapshot)?

    /// `minimumInterval`: spawning a Node CLI every second would cost more
    /// than the number is worth, so a reading younger than this is reused.
    init(executable: @escaping () -> String? = OpenClawProvider.locate,
         timeout: TimeInterval = 10, minimumInterval: TimeInterval = 15) {
        self.executable = executable
        self.timeout = timeout
        self.minimumInterval = minimumInterval
    }

    nonisolated var isVisibleWhenAbsent: Bool { false }

    nonisolated var signInRoute: SignInRoute {
        .guidance(L10n.t("Install OpenClaw — the notch reads its session list with `openclaw sessions list --json`."))
    }

    nonisolated static func locate() -> String? {
        candidatePaths.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    func fetchSnapshot() async throws -> ProviderSnapshot {
        let preferred = OpenClawUsage.preferredSessionKey
        if let cached, cached.key == preferred, Date().timeIntervalSince(cached.at) < minimumInterval { return cached.snapshot }
        guard let path = executable() else { throw OpenClawError.notInstalled }
        let data = try await Self.run(path: path, arguments: ["sessions", "list", "--json"], timeout: timeout)
        let reading = try OpenClawUsage.parse(data, preferredKey: preferred)
        Log.usage.debug("openclaw context -> \(reading.totalTokens, privacy: .public)/\(reading.contextTokens, privacy: .public)")
        let snapshot = ProviderSnapshot(
            id: id, displayName: displayName, glyph: glyph,
            fidelity: .official,
            status: reading.isFresh ? .ok : .stale(since: reading.updatedAt ?? Date()),
            windows: [OpenClawUsage.window(from: reading)],
            headlineID: "context",
            plan: reading.model
        )
        cached = (Date(), preferred, snapshot)
        return snapshot
    }

    /// Runs the CLI off the actor, killing it if it outlives `timeout`.
    static func run(path: String, arguments: [String], timeout: TimeInterval) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: path)
                process.arguments = arguments
                var environment = ProcessInfo.processInfo.environment
                // The CLI is a Node script; a GUI app's PATH lacks Homebrew.
                environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:" + (environment["PATH"] ?? "")
                environment["NO_COLOR"] = "1"
                process.environment = environment
                let out = Pipe()
                process.standardOutput = out
                process.standardError = FileHandle.nullDevice
                do { try process.run() } catch {
                    continuation.resume(throwing: OpenClawError.unavailable(error.localizedDescription))
                    return
                }
                let killer = DispatchWorkItem { if process.isRunning { process.terminate() } }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killer)
                let data = out.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                killer.cancel()
                if process.terminationReason == .uncaughtSignal {
                    continuation.resume(throwing: OpenClawError.unavailable(L10n.t("timed out")))
                } else if process.terminationStatus != 0 {
                    continuation.resume(throwing: OpenClawError.unavailable("exit \(process.terminationStatus)"))
                } else {
                    continuation.resume(returning: data)
                }
            }
        }
    }
}
