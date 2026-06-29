import AppKit
import SwiftUI
import XCTest
@testable import VibePetApp
import VibePetCore

/// Regression guard for the bubble-question layout: the card's body is hosted in a
/// `ThinBubbleScrollView` whose inner `GeometryReader` has no intrinsic height, so
/// it once collapsed to ~nothing during the off-screen `fittingSize` measurement
/// `PetWindowSurface` uses to size the bubble window. The window was then sized to
/// roughly header+footer and the rendered body was squeezed behind a scroll. The
/// card now drives the scroll viewport from its measured content height, so a single
/// question shows all its options without scrolling and the measured size hugs it.
@MainActor
final class QuestionCardSizingTests: XCTestCase {
    private func fittingHeight(for view: some View) -> CGFloat {
        let hosting = NSHostingController(rootView: view)
        hosting.view.layoutSubtreeIfNeeded()
        return hosting.view.fittingSize.height
    }

    private func makeCard(
        questions: [QuestionItem],
        context: QuestionConversationContext?
    ) -> QuestionCard {
        QuestionCard(
            content: QuestionContent(title: "Pick an option", questions: questions),
            source: SourceInfo(
                tool: .claudeCode,
                projectName: "VibePet",
                sessionShortId: "42b433",
                cwd: "/Users/x/Documents/GitHub/VibePet"
            ),
            conversationContext: context,
            tailEdge: .bottom,
            tailOffsetX: 0,
            presentation: ApprovalPresentation(pendingCount: 0)
        )
    }

    func testMeasuredHeightContainsAllOptionsWithoutCollapsing() {
        let card = makeCard(
            questions: [
                QuestionItem(
                    header: "Plan",
                    prompt: "远离人群，看星空、生火、听虫鸣。你更想去哪里露营度过周末？",
                    options: [
                        QuestionOption(label: "山地营地", detail: "海拔高，夜里能看银河", allowsFreeform: false),
                        QuestionOption(label: "湖边营地", detail: "清晨有雾，适合钓鱼", allowsFreeform: false),
                        QuestionOption(label: "海边营地", detail: "听潮声入睡", allowsFreeform: false),
                    ],
                    multiSelect: false
                ),
                QuestionItem(
                    header: "Budget",
                    prompt: "预算大概是多少？",
                    options: [
                        QuestionOption(label: "经济", detail: nil, allowsFreeform: false),
                        QuestionOption(label: "舒适", detail: nil, allowsFreeform: false),
                    ],
                    multiSelect: false
                ),
            ],
            context: QuestionConversationContext(
                latestUserPrompt: "帮我安排一个周末的露营计划",
                agentSummary: "我需要先确认几个偏好"
            )
        )
        // A collapsed body would measure ~header+footer (≈120pt). The first question
        // (prompt + three option cards + the context turns) needs substantially more.
        XCTAssertGreaterThan(fittingHeight(for: card), 240)
    }

    func testMeasuredHeightStaysBoundedForOverflowingContent() {
        let manyOptions = (0..<8).map { index in
            QuestionOption(
                label: "选项 \(index)",
                detail: "这是一个相对较长的说明，用来撑高每个选项卡片的高度。",
                allowsFreeform: false
            )
        }
        let card = makeCard(
            questions: [
                QuestionItem(header: "Big", prompt: "一个有很多选项的问题。", options: manyOptions, multiSelect: true),
            ],
            context: nil
        )
        // Body scroll is capped at `interactiveBodyMaxHeight`; the whole card stays
        // within that plus header/footer chrome rather than growing unbounded.
        XCTAssertLessThan(fittingHeight(for: card), BubbleTheme.interactiveBodyMaxHeight + 200)
    }
}
