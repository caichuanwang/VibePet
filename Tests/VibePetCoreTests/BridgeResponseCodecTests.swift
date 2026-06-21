import XCTest
@testable import VibePetCore

final class BridgeResponseCodecTests: XCTestCase {
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    func testApprovalAllowOnceRoundTrips() throws {
        try assertRoundTrip(.approval(.allowOnce))
    }

    func testApprovalAllowAlwaysPreservesScopeHint() throws {
        try assertRoundTrip(.approval(.allowAlways(scopeHint: "Bash")))
    }

    func testApprovalDenyPreservesReason() throws {
        try assertRoundTrip(.approval(.deny(reason: "Too risky")))
    }

    func testQuestionAnswerRoundTrips() throws {
        try assertRoundTrip(
            .question(
                QuestionAnswer(answers: ["strategy": "Fast, Small", "notes": "Keep the diff small"])
            )
        )
    }

    func testDeferRoundTrips() throws {
        try assertRoundTrip(.defer)
    }

    private func assertRoundTrip(
        _ response: BridgeResponse,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let requestId = UUID(uuidString: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")!
        let envelope = BridgeResponseEnvelope(requestId: requestId, response: response)

        let data = try encoder.encode(envelope)
        let decoded = try decoder.decode(BridgeResponseEnvelope.self, from: data)

        XCTAssertEqual(decoded.requestId, requestId, file: file, line: line)
        XCTAssertEqual(decoded.response, response, file: file, line: line)
        XCTAssertEqual(decoded, envelope, file: file, line: line)
    }
}
