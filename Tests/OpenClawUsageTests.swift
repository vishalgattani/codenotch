import XCTest
@testable import Codenotch

/// Pinned to `openclaw sessions list --json` from OpenClaw 2026.10.3, recorded
/// on 2026-10-14 and trimmed to the fields the provider reads.
final class OpenClawUsageTests: XCTestCase {
    private let recorded = """
    Config warnings: none
    {"path":"/Users/me/.openclaw/agents/main/agent/openclaw-agent.sqlite","count":3,"sessions":[
     {"key":"agent:main:main","updatedAt":1792041135516,"inputTokens":11493,"outputTokens":3,
      "totalTokens":11493,"totalTokensFresh":true,"contextTokens":65536,
      "model":"mlx-community/Qwen3.6-35B-A3B-4bit","modelProvider":"mlx-main","participants":[]},
     {"key":"agent:main:example-session","updatedAt":1792040718665,"inputTokens":255,
      "outputTokens":10,"totalTokens":10562,"totalTokensFresh":true,"contextTokens":65536,
      "model":"mlx-community/Qwen3.6-35B-A3B-4bit","modelProvider":"mlx-main"},
     {"key":"agent:main:claude-tuning","updatedAt":1792039072597,"totalTokens":26142,
      "totalTokensFresh":true,"contextTokens":65536,
      "model":"mlx-community/Qwen3.6-35B-A3B-4bit","modelProvider":"mlx-main"}]}
    """

    func testTheChosenSessionIsPreferred() throws {
        let reading = try OpenClawUsage.parse(Data(recorded.utf8), preferredKey: "agent:main:example-session")
        XCTAssertEqual(reading.sessionKey, "agent:main:example-session")
        XCTAssertEqual(reading.totalTokens, 10562)
        XCTAssertEqual(reading.contextTokens, 65536)
        XCTAssertEqual(reading.model, "mlx-community/Qwen3.6-35B-A3B-4bit")
        XCTAssertTrue(reading.isFresh)
        XCTAssertEqual(reading.usedFraction, 10562.0 / 65536.0, accuracy: 1e-9)
        XCTAssertEqual(reading.updatedAt, Date(timeIntervalSince1970: 1792040718.665))
    }

    func testTheMostRecentSessionStandsInWhenTheChosenOneIsMissing() throws {
        let reading = try OpenClawUsage.parse(Data(recorded.utf8), preferredKey: "agent:main:nope")
        XCTAssertEqual(reading.sessionKey, "agent:main:main")
        XCTAssertEqual(reading.totalTokens, 11493)
    }

    func testWithNoSessionChosenTheMostRecentIsShown() throws {
        let reading = try OpenClawUsage.parse(Data(recorded.utf8), preferredKey: nil)
        XCTAssertEqual(reading.sessionKey, "agent:main:main")
    }

    func testAnOldCountIsNotFresh() throws {
        let json = #"{"sessions":[{"key":"a","updatedAt":1,"totalTokens":500,"totalTokensFresh":false,"contextTokens":1000}]}"#
        let reading = try OpenClawUsage.parse(Data(json.utf8))
        XCTAssertFalse(reading.isFresh)
        XCTAssertEqual(reading.usedFraction, 0.5)
    }

    func testSessionsWithoutAWindowAreSkipped() {
        let json = #"{"sessions":[{"key":"a","totalTokens":500}]}"#
        XCTAssertThrowsError(try OpenClawUsage.parse(Data(json.utf8))) {
            XCTAssertEqual($0 as? OpenClawError, .noSessions)
        }
    }

    func testGarbageIsRejected() {
        XCTAssertThrowsError(try OpenClawUsage.parse(Data("not json".utf8))) {
            XCTAssertEqual($0 as? OpenClawError, .invalidResponse)
        }
    }

    func testTheWindowCarriesModelTokensAndKey() throws {
        let window = OpenClawUsage.window(from: try OpenClawUsage.parse(Data(recorded.utf8), preferredKey: "agent:main:example-session"))
        XCTAssertEqual(window.id, "context")
        XCTAssertEqual(window.usedFraction ?? 0, 0.161, accuracy: 0.001)
        let detail = try XCTUnwrap(window.detail)
        XCTAssertTrue(detail.contains("mlx-community/Qwen3.6-35B-A3B-4bit"))
        XCTAssertTrue(detail.contains("agent:main:example-session"))
        XCTAssertTrue(detail.contains("65,536") || detail.contains("65536"))
    }

    func testTheGlyphIsTheCrab() {
        XCTAssertEqual(ProviderGlyph.openclaw.emoji, "🦀")
        XCTAssertNil(ProviderGlyph.claude.emoji)
    }
}
