import XCTest
@testable import VibePetApp
import VibePetCore

final class SpeechBubbleMarkdownTests: XCTestCase {
    func testMarkdownBlocksPreserveParagraphsListsAndCodeFences() {
        let markdown = """
        已完成：

        - swift build 通过
        - `swift test` 通过

        ```swift
        let result = "ok"
        ```
        """

        XCTAssertEqual(
            BubbleMarkdownBlock.blocks(from: markdown),
            [
                BubbleMarkdownBlock(kind: .paragraph, text: "已完成："),
                BubbleMarkdownBlock(kind: .bullet, text: "swift build 通过"),
                BubbleMarkdownBlock(kind: .bullet, text: "`swift test` 通过"),
                BubbleMarkdownBlock(kind: .code, text: "let result = \"ok\"")
            ]
        )
    }

    func testMarkdownBlocksPreserveQuotedContextAndNumberedLists() {
        let markdown = """
        > 需要人工确认

        1. 检查配置
        2. 重启 agent
        """

        XCTAssertEqual(
            BubbleMarkdownBlock.blocks(from: markdown),
            [
                BubbleMarkdownBlock(kind: .quote, text: "需要人工确认"),
                BubbleMarkdownBlock(kind: .numbered(1), text: "检查配置"),
                BubbleMarkdownBlock(kind: .numbered(2), text: "重启 agent")
            ]
        )
    }

    func testBubbleScrollThumbStaysThinLikeDashboardPanel() {
        XCTAssertLessThanOrEqual(BubbleTheme.scrollThumbWidth, 2)
    }

    func testStatusBubbleProjectionIsCompactWithNoFooter() {
        let projection = SpeechBubble.layoutProjection(
            for: .status(StatusContent(text: "Running tests")),
            source: SourceInfo(
                tool: .codex,
                projectName: "VibePet",
                sessionShortId: "abc123",
                cwd: "/tmp/VibePet",
                jumpTarget: JumpTarget(terminalApp: "Terminal")
            )
        )

        XCTAssertEqual(projection.sourceLabel, "Codex · VibePet · abc123")
        XCTAssertEqual(projection.bodyText, "Running tests")
        XCTAssertTrue(projection.hasSourceHeader)
        XCTAssertFalse(projection.hasFooter)
        XCTAssertTrue(projection.supportsBodyJumpBack)
        XCTAssertTrue(projection.pausesAutoDismissOnHover)
        XCTAssertGreaterThanOrEqual(projection.autoDismissSeconds, 6)
        XCTAssertLessThanOrEqual(projection.autoDismissSeconds, 8)
    }
}
