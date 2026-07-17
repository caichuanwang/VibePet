import XCTest
@testable import VibePetCore

final class M4AdapterCompatibilityTests: XCTestCase {
    func testClaudeTranscriptReaderRejectsOversizedRegularFile() throws {
        let file = try M4TemporaryFile(
            contents: Data(repeating: 0x61, count: ClaudeCodeAdapter.maximumTranscriptBytes + 1)
        )

        XCTAssertNil(ClaudeCodeAdapter.readTranscriptSummary(path: file.url.path))
    }

    func testClaudeTranscriptReaderInspectsOnlyLastTwoThousandLines() throws {
        let oldAssistant = try transcriptLine(text: "too old")
        let trailing = Array(repeating: Data("{}\n".utf8), count: ClaudeCodeAdapter.maximumTranscriptLines)
        let file = try M4TemporaryFile(contents: ([oldAssistant] + trailing).reduce(into: Data(), +=))

        XCTAssertNil(ClaudeCodeAdapter.readTranscriptSummary(path: file.url.path))
    }

    func testClaudeTranscriptReaderSkipsMalformedTailWithinBound() throws {
        var contents = try transcriptLine(text: "bounded summary")
        contents.append(Data("not-json\n".utf8))
        let file = try M4TemporaryFile(contents: contents)

        XCTAssertEqual(
            ClaudeCodeAdapter.readTranscriptSummary(path: file.url.path),
            "bounded summary"
        )
    }

    func testClaudeTranscriptReaderRejectsNonRegularFile() throws {
        let directory = try M4TemporaryDirectory()

        XCTAssertNil(ClaudeCodeAdapter.readTranscriptSummary(path: directory.url.path))
    }

    func testClaudeUnknownMalformedAndMissingEventAreIgnored() throws {
        let adapter = ClaudeCodeAdapter()
        let payloads = [
            Data("not-json".utf8),
            try json(["session_id": "s1"]),
            try json(["hook_event_name": "FutureEvent", "session_id": "s1"]),
        ]

        for payload in payloads {
            XCTAssertNil(try adapter.parseEvent(stdin: payload, env: [:]))
            XCTAssertNil(try adapter.parseAgentEvent(stdin: payload, env: [:]))
        }
    }

    func testCodexSessionIdentifiersAreLimitedToFixtureBackedFields() throws {
        let adapter = CodexAdapter()
        let hook = try XCTUnwrap(adapter.parseEvent(
            stdin: fixture(tool: "codex", name: "permission-request-shell.json"),
            env: [:]
        ))
        let notify = try XCTUnwrap(adapter.parseEvent(
            stdin: fixture(tool: "codex", name: "notify-agent-turn-complete.json"),
            env: [:]
        ))

        XCTAssertEqual(hook.source.sessionID, "9f8e7d6c5b4a3210")
        XCTAssertEqual(notify.source.sessionID, "c0ffee123456")
    }

    func testCodexUnknownMalformedAndMissingEventAreIgnored() throws {
        let adapter = CodexAdapter()
        let payloads = [
            Data("not-json".utf8),
            try json(["session_id": "s1"]),
            try json(["hook_event_name": "FutureEvent", "session_id": "s1"]),
        ]

        for payload in payloads {
            XCTAssertNil(try adapter.parseEvent(stdin: payload, env: [:]))
            XCTAssertNil(try adapter.parseAgentEvent(stdin: payload, env: [:]))
        }
    }

    private func transcriptLine(text: String) throws -> Data {
        var data = try json([
            "type": "assistant",
            "message": [
                "content": [["type": "text", "text": text]],
            ],
        ])
        data.append(0x0A)
        return data
    }

    private func json(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object)
    }

    private func fixture(tool: String, name: String) -> Data {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/\(tool)/\(name)")
        return (try? Data(contentsOf: url)) ?? Data()
    }
}

private final class M4TemporaryFile {
    let url: URL

    init(contents: Data) throws {
        url = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("vp-m4-\(UUID().uuidString).jsonl", isDirectory: false)
        try contents.write(to: url, options: .atomic)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}

private final class M4TemporaryDirectory {
    let url: URL

    init() throws {
        url = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("vp-m4-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}
