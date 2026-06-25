import XCTest
@testable import VibePetCore

final class BridgeEnvelopeCodecTests: XCTestCase {
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    func testApprovalContentRoundTrips() throws {
        let envelope = makeEnvelope(
            content: .approval(
                ApprovalContent(
                    title: "Claude wants to run a command",
                    risk: .high,
                    preview: .command(text: "rm -rf build"),
                    allowLabel: "Allow once",
                    denyLabel: "Deny",
                    alwaysAllow: AlwaysAllowOption(label: "Always allow Bash", scopeHint: "Bash"),
                    requiresTerminalApproval: false
                )
            )
        )

        try assertRoundTrip(envelope)
    }

    func testQuestionContentRoundTrips() throws {
        let envelope = makeEnvelope(
            content: .question(
                QuestionContent(
                    title: "Pick an approach",
                    questions: [
                        QuestionItem(
                            header: "strategy",
                            prompt: "Which path should I take?",
                            options: [
                                QuestionOption(label: "Fast", detail: "Smallest diff", allowsFreeform: false),
                                QuestionOption(label: "Other", detail: nil, allowsFreeform: true)
                            ],
                            multiSelect: true
                        )
                    ]
                )
            )
        )

        try assertRoundTrip(envelope)
    }

    func testCompletionContentRoundTrips() throws {
        let envelope = makeEnvelope(
            content: .completion(CompletionContent(markdownSummary: "Done", isError: false))
        )

        try assertRoundTrip(envelope)
    }

    func testStatusContentRoundTrips() throws {
        let envelope = makeEnvelope(content: .status(StatusContent(text: "Thinking")))

        try assertRoundTrip(envelope)
    }

    func testSourceInfoPreservesStableSessionIDAndJumpTarget() throws {
        let envelope = BridgeEnvelope(
            version: 1,
            requestId: UUID(uuidString: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")!,
            source: SourceInfo(
                tool: .codex,
                projectName: "VibePet",
                sessionID: "codex-session-full",
                sessionShortId: "codex-",
                cwd: "/tmp/VibePet",
                jumpTarget: JumpTarget(
                    terminalApp: "Terminal",
                    workspaceName: "VibePet",
                    paneTitle: "Codex",
                    workingDirectory: "/tmp/VibePet",
                    terminalSessionID: "tab-1",
                    terminalTTY: "/dev/ttys002"
                )
            ),
            content: .status(StatusContent(text: "Working"))
        )

        let data = try encoder.encode(envelope)
        let decoded = try decoder.decode(BridgeEnvelope.self, from: data)

        XCTAssertEqual(decoded, envelope)
        XCTAssertEqual(decoded.source.sessionID, "codex-session-full")
        XCTAssertEqual(decoded.source.sessionShortId, "codex-")
        XCTAssertNotEqual(decoded.source.sessionID, decoded.source.sessionShortId)
        XCTAssertEqual(decoded.source.jumpTarget?.terminalSessionID, "tab-1")
        XCTAssertEqual(decoded.source.jumpTarget?.terminalTTY, "/dev/ttys002")
    }

    func testSourceInfoMissingSessionIDUsesDeterministicFallback() throws {
        let json = """
        {
          "version": 1,
          "requestId": "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
          "source": {
            "tool": "codex",
            "projectName": "VibePet",
            "cwd": "/tmp/VibePet"
          },
          "content": {
            "type": "status",
            "status": {
              "text": "Working"
            }
          }
        }
        """
        let data = Data(json.utf8)

        let first = try decoder.decode(BridgeEnvelope.self, from: data)
        let second = try decoder.decode(BridgeEnvelope.self, from: data)

        XCTAssertEqual(first.source.sessionID, "unknown-codex")
        XCTAssertEqual(second.source.sessionID, first.source.sessionID)
    }

    func testActionPreviewVariantsRoundTrip() throws {
        let previews: [ActionPreview] = [
            .command(text: "swift test"),
            .fileChange(path: "Package.swift", added: 8, removed: 2),
            .fileRead(path: "README.md"),
            .network(target: "https://example.com"),
            .generic(summary: "A generic operation")
        ]

        for preview in previews {
            let data = try encoder.encode(preview)
            let decoded = try decoder.decode(ActionPreview.self, from: data)
            XCTAssertEqual(decoded, preview)
        }
    }

    func testNeedsResponseClassification() {
        XCTAssertTrue(
            BubbleContent.approval(
                ApprovalContent(
                    title: "Approve",
                    risk: .low,
                    preview: .generic(summary: "Preview"),
                    allowLabel: "Allow once",
                    denyLabel: "Deny",
                    alwaysAllow: nil,
                    requiresTerminalApproval: false
                )
            ).needsResponse
        )
        XCTAssertTrue(
            BubbleContent.question(
                QuestionContent(
                    title: "Question",
                    questions: [
                        QuestionItem(
                            header: "choice",
                            prompt: "Choose",
                            options: [],
                            multiSelect: false
                        )
                    ]
                )
            ).needsResponse
        )
        XCTAssertFalse(BubbleContent.completion(CompletionContent(markdownSummary: "Done", isError: false)).needsResponse)
        XCTAssertFalse(BubbleContent.status(StatusContent(text: "Idle")).needsResponse)
    }

    private func makeEnvelope(content: BubbleContent) -> BridgeEnvelope {
        BridgeEnvelope(
            version: 1,
            requestId: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
            source: SourceInfo(
                tool: .claudeCode,
                projectName: "VibePet",
                sessionID: "session-full-abc123",
                sessionShortId: "abc123",
                cwd: "/tmp/VibePet"
            ),
            content: content
        )
    }

    private func assertRoundTrip(_ envelope: BridgeEnvelope, file: StaticString = #filePath, line: UInt = #line) throws {
        let data = try encoder.encode(envelope)
        let decoded = try decoder.decode(BridgeEnvelope.self, from: data)
        XCTAssertEqual(decoded, envelope, file: file, line: line)
    }
}
