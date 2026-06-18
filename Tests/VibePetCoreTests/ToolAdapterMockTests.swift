import XCTest
@testable import VibePetCore

final class ToolAdapterMockTests: XCTestCase {
    func testMockAdapterParsesRecognizedEvent() throws {
        let adapter = MockToolAdapter()
        let envelope = try adapter.parseEvent(stdin: Data("recognized".utf8), env: ["PWD": "/tmp/VibePet"])

        XCTAssertEqual(envelope?.source.tool, .claudeCode)
        XCTAssertEqual(envelope?.source.cwd, "/tmp/VibePet")
        XCTAssertEqual(envelope?.content, .status(StatusContent(text: "recognized event")))
    }

    func testMockAdapterReturnsNilForUnrecognizedEvent() throws {
        let adapter = MockToolAdapter()

        XCTAssertNil(try adapter.parseEvent(stdin: Data("ignored".utf8), env: [:]))
    }

    func testMockAdapterEncodesResponseData() {
        let adapter = MockToolAdapter()
        let envelope = BridgeEnvelope(
            requestId: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
            source: SourceInfo(tool: .claudeCode, projectName: nil, sessionShortId: nil, cwd: nil),
            content: .status(StatusContent(text: "recognized event"))
        )

        let data = adapter.encodeResponse(.defer, for: envelope)

        XCTAssertFalse(data.isEmpty)
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "defer:11111111-2222-3333-4444-555555555555")
    }
}

private struct MockToolAdapter: ToolAdapter {
    let tool: ToolKind = .claudeCode

    func parseEvent(stdin: Data, env: [String: String]) throws -> BridgeEnvelope? {
        guard String(decoding: stdin, as: UTF8.self) == "recognized" else {
            return nil
        }

        return BridgeEnvelope(
            requestId: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
            source: SourceInfo(
                tool: tool,
                projectName: "VibePet",
                sessionShortId: "abc123",
                cwd: env["PWD"]
            ),
            content: .status(StatusContent(text: "recognized event"))
        )
    }

    func encodeResponse(_ response: BridgeResponse, for envelope: BridgeEnvelope) -> Data {
        Data("\(response.kind):\(envelope.requestId.uuidString.lowercased())".utf8)
    }
}

private extension BridgeResponse {
    var kind: String {
        switch self {
        case .approval:
            "approval"
        case .question:
            "question"
        case .defer:
            "defer"
        }
    }
}
