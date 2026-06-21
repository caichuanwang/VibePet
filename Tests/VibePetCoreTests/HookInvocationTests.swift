import XCTest
@testable import VibePetCore

/// M6-1 (CLI routing): `VibePetHooks` selects its `ToolAdapter` from an explicit
/// `--tool` identifier (Codex → `CodexAdapter`, absent/default → `ClaudeCodeAdapter`),
/// and reads the Codex `notify` payload from argv (`--notify`) instead of stdin.
final class HookInvocationTests: XCTestCase {
    func testCodexArgumentSelectsCodexAdapter() {
        XCTAssertEqual(HookInvocation.adapter(forTool: "codex").tool, .codex)
    }

    func testDefaultSelectsClaudeAdapter() {
        XCTAssertEqual(HookInvocation.adapter(forTool: nil).tool, .claudeCode)
        XCTAssertEqual(HookInvocation.adapter(forTool: "claudeCode").tool, .claudeCode)
        XCTAssertEqual(HookInvocation.adapter(forTool: "unknown").tool, .claudeCode)
    }

    func testToolArgumentParsing() {
        XCTAssertEqual(HookInvocation.toolArgument(in: ["VibePetHooks", "--tool", "codex"]), "codex")
        XCTAssertNil(HookInvocation.toolArgument(in: ["VibePetHooks"]))
        XCTAssertNil(HookInvocation.toolArgument(in: ["VibePetHooks", "--tool"]))
    }

    func testNotifyFlagDetection() {
        XCTAssertTrue(HookInvocation.isNotify(arguments: ["VibePetHooks", "--tool", "codex", "--notify", "{}"]))
        XCTAssertFalse(HookInvocation.isNotify(arguments: ["VibePetHooks", "--tool", "codex"]))
    }

    func testEventDataPrefersNotifyArgvOverStdin() {
        let stdin = Data("STDIN".utf8)
        let argv = ["VibePetHooks", "--tool", "codex", "--notify", "{\"type\":\"agent-turn-complete\"}"]
        let data = HookInvocation.eventData(arguments: argv, stdin: stdin)
        XCTAssertEqual(String(data: data, encoding: .utf8), "{\"type\":\"agent-turn-complete\"}")
    }

    func testEventDataUsesStdinWhenNotNotify() {
        let stdin = Data("STDIN".utf8)
        let data = HookInvocation.eventData(arguments: ["VibePetHooks", "--tool", "codex"], stdin: stdin)
        XCTAssertEqual(data, stdin)
    }
}
