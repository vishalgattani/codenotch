import Foundation

/// One OpenClaw session's context fill, as `openclaw sessions list --json`
/// reports it (recorded from OpenClaw 2026.10.3 on 2026-10-14, trimmed):
///
///     {"count":5,"sessions":[
///       {"key":"agent:main:example-session","updatedAt":1792040718665,
///        "totalTokens":10562,"totalTokensFresh":true,"contextTokens":65536,
///        "model":"mlx-community/Qwen3.6-35B-A3B-4bit","modelProvider":"mlx-main"}, …]}
///
/// `totalTokens` is what the last turn put in the model's context and
/// `contextTokens` the window it was run with, so their ratio is how full the
/// agent's context is. `totalTokensFresh: false` means OpenClaw is carrying an
/// older count forward, which is shown as stale rather than as the present.
struct OpenClawReading: Equatable {
    let sessionKey: String
    let model: String?
    let modelProvider: String?
    let totalTokens: Int
    let contextTokens: Int
    let isFresh: Bool
    let updatedAt: Date?

    var usedFraction: Double { Double(totalTokens) / Double(contextTokens) }

    var detail: String {
        let model = self.model ?? L10n.t("Unknown model")
        return "\(model) · \(totalTokens.formatted()) / \(contextTokens.formatted()) tokens · \(sessionKey)"
    }
}

enum OpenClawError: LocalizedError, Equatable {
    case notInstalled
    case unavailable(String)
    case invalidResponse
    case noSessions

    var errorDescription: String? {
        switch self {
        case .notInstalled: return L10n.t("OpenClaw's CLI was not found")
        case .unavailable(let why): return L10n.t("OpenClaw did not answer: \(why)")
        case .invalidResponse: return L10n.t("OpenClaw returned an unreadable session list")
        case .noSessions: return L10n.t("OpenClaw has no session with a context window yet")
        }
    }
}

enum OpenClawUsage {
    /// The UserDefaults key holding the session to follow, set in Settings.
    /// Kept out of the source because a session key can name a private chat.
    static let sessionKeyDefault = "openclawSessionKey"

    static var preferredSessionKey: String? {
        let key = UserDefaults.standard.string(forKey: sessionKeyDefault)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return key?.isEmpty == false ? key : nil
    }

    private struct Response: Decodable {
        let sessions: [Session]
    }

    private struct Session: Decodable {
        let key: String
        let updatedAt: Double?
        let totalTokens: Int?
        let totalTokensFresh: Bool?
        let contextTokens: Int?
        let model: String?
        let modelProvider: String?
    }

    static func parse(_ data: Data, preferredKey: String? = preferredSessionKey) throws -> OpenClawReading {
        // The CLI can print a banner or warning before the JSON; read from the
        // first brace on.
        let start = data.firstIndex(of: UInt8(ascii: "{")) ?? data.startIndex
        guard let response = try? JSONDecoder().decode(Response.self, from: data[start...]) else {
            throw OpenClawError.invalidResponse
        }
        let usable = response.sessions.filter {
            ($0.contextTokens ?? 0) > 0 && $0.totalTokens != nil
        }
        let chosen = preferredKey.flatMap { key in usable.first { $0.key == key } }
            ?? usable.max { ($0.updatedAt ?? 0) < ($1.updatedAt ?? 0) }
        guard let session = chosen, let total = session.totalTokens,
              let context = session.contextTokens else {
            throw OpenClawError.noSessions
        }
        return OpenClawReading(
            sessionKey: session.key,
            model: session.model,
            modelProvider: session.modelProvider,
            totalTokens: max(total, 0),
            contextTokens: context,
            isFresh: session.totalTokensFresh ?? true,
            updatedAt: session.updatedAt.map { Date(timeIntervalSince1970: $0 / 1000) }
        )
    }

    static func window(from reading: OpenClawReading) -> LimitWindow {
        LimitWindow(
            id: "context",
            label: L10n.t("Context"),
            usedFraction: reading.usedFraction,
            detail: reading.detail
        )
    }
}
