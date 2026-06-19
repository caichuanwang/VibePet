import XCTest
@testable import VibePetCore

/// M4-3a spike: a Claude Code `PreToolUse` hook cannot grant a persistent allow
/// (see `Tests/Fixtures/claude/allow-always-spike-notes.md`). These tests pin the
/// "unsupported" conclusion so a regression that silently re-enables a bogus
/// allowAlways branch is caught.
final class ClaudeCodeAllowAlwaysSpikeTests: XCTestCase {
    private let adapter = ClaudeCodeAdapter()

    func testParsedApprovalHasNoAlwaysAllowOption() throws {
        for fixture in ["pretooluse-bash.json", "pretooluse-edit.json", "pretooluse-webfetch.json"] {
            let envelope = try XCTUnwrap(adapter.parseEvent(stdin: fixtureData(fixture), env: [:]))
            guard case let .approval(content) = envelope.content else {
                return XCTFail("Expected .approval for \(fixture)")
            }
            XCTAssertNil(content.alwaysAllow, "\(fixture) must not advertise always-allow (unsupported)")
        }
    }

    func testAllowAlwaysDecodesAsPlainAllowNotAPersistentBranch() throws {
        // Defensive: even if a stale client sends allowAlways, the encoder emits a
        // plain one-time allow — never a distinct persistent-allow output.
        let data = adapter.encodeResponse(
            .approval(.allowAlways(scopeHint: "Bash")),
            for: sampleEnvelope()
        )
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let output = try XCTUnwrap(object["hookSpecificOutput"] as? [String: Any])
        XCTAssertEqual(output["permissionDecision"] as? String, "allow")
        // No persistent/scope field leaks into the hook output.
        XCTAssertNil(output["scopeHint"])
        XCTAssertNil(output["alwaysAllow"])
    }

    // MARK: - Helpers

    private func sampleEnvelope() -> BridgeEnvelope {
        BridgeEnvelope(
            requestId: UUID(),
            source: SourceInfo(tool: .claudeCode, projectName: "VibePet", sessionShortId: "a1b2c3", cwd: nil),
            content: .approval(ApprovalContent(
                title: "运行命令",
                risk: .medium,
                preview: .command(text: "swift test"),
                alwaysAllow: nil,
                requiresTerminalApproval: false
            ))
        )
    }

    private func fixtureData(_ name: String) -> Data {
        (try? Data(contentsOf: URL(fileURLWithPath:
            URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Fixtures/claude/\(name)")
                .path
        ))) ?? Data()
    }
}
