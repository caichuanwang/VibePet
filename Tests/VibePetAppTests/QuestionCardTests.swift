import XCTest
@testable import VibePetApp
import VibePetCore

@MainActor
final class QuestionCardTests: XCTestCase {
    func testSubmitDisabledWhenOnlyOneOfMultipleQuestionsIsAnswered() {
        XCTAssertFalse(QuestionCard.hasCompleteSelection(
            questions: questions,
            selections: ["Database": ["SQLite"]],
            freeformText: [:]
        ))
    }

    func testSubmitEnabledWhenEveryQuestionIsAnswered() {
        XCTAssertTrue(QuestionCard.hasCompleteSelection(
            questions: questions,
            selections: [
                "Database": ["SQLite"],
                "Runtime": ["Local"],
            ],
            freeformText: [:]
        ))
    }

    func testFreeformSelectionRequiresNonEmptyText() {
        XCTAssertFalse(QuestionCard.hasCompleteSelection(
            questions: questions,
            selections: [
                "Database": ["Other"],
                "Runtime": ["Local"],
            ],
            freeformText: ["Database": "   "]
        ))

        XCTAssertTrue(QuestionCard.hasCompleteSelection(
            questions: questions,
            selections: [
                "Database": ["Other"],
                "Runtime": ["Local"],
            ],
            freeformText: ["Database": "DuckDB"]
        ))
    }

    func testPagingStateStartsOnFirstPageAndSubmitHiddenUntilFinalPage() {
        let first = QuestionCard.pagingState(
            questionCount: questions.count,
            currentIndex: 0,
            questions: questions,
            selections: ["Database": ["SQLite"]],
            freeformText: [:]
        )
        let final = QuestionCard.pagingState(
            questionCount: questions.count,
            currentIndex: 1,
            questions: questions,
            selections: [
                "Database": ["SQLite"],
                "Runtime": ["Local"],
            ],
            freeformText: [:]
        )

        XCTAssertEqual(first.currentIndex, 0)
        XCTAssertFalse(first.canGoPrevious)
        XCTAssertTrue(first.canGoNext)
        XCTAssertFalse(first.showsSubmit)
        XCTAssertTrue(final.canGoPrevious)
        XCTAssertFalse(final.canGoNext)
        XCTAssertTrue(final.showsSubmit)
    }

    func testNextBlockedUntilCurrentQuestionValid() {
        let empty = QuestionCard.pagingState(
            questionCount: questions.count,
            currentIndex: 0,
            questions: questions,
            selections: [:],
            freeformText: [:]
        )
        let answered = QuestionCard.pagingState(
            questionCount: questions.count,
            currentIndex: 0,
            questions: questions,
            selections: ["Database": ["SQLite"]],
            freeformText: [:]
        )

        XCTAssertFalse(empty.canGoNext)
        XCTAssertEqual(QuestionCard.nextIndex(from: 0, questions: questions, selections: [:], freeformText: [:]), 0)
        XCTAssertTrue(answered.canGoNext)
        XCTAssertEqual(
            QuestionCard.nextIndex(
                from: 0,
                questions: questions,
                selections: ["Database": ["SQLite"]],
                freeformText: [:]
            ),
            1
        )
    }

    func testSelectionsAndFreeformArePreservedAcrossPagingHelpers() {
        let selections: [String: Set<String>] = [
            "Database": ["Other"],
            "Runtime": ["Local"],
        ]
        let freeform = ["Database": "DuckDB"]

        XCTAssertEqual(QuestionCard.selectedLabels(for: questions[0], selections: selections), ["Other"])
        XCTAssertEqual(QuestionCard.freeformValue(for: questions[0], freeformText: freeform), "DuckDB")
        XCTAssertEqual(QuestionCard.selectedLabels(for: questions[1], selections: selections), ["Local"])
    }

    func testSingleQuestionShowsSubmitImmediately() {
        let state = QuestionCard.pagingState(
            questionCount: 1,
            currentIndex: 0,
            questions: [questions[0]],
            selections: [:],
            freeformText: [:]
        )

        XCTAssertTrue(state.showsSubmit)
        XCTAssertFalse(state.canGoPrevious)
        XCTAssertFalse(state.canGoNext)
    }

    func testSubmitEnabledOnlyWhenEveryQuestionIsValidOnFinalPage() {
        let partial = QuestionCard.pagingState(
            questionCount: questions.count,
            currentIndex: 1,
            questions: questions,
            selections: ["Database": ["SQLite"]],
            freeformText: [:]
        )
        let complete = QuestionCard.pagingState(
            questionCount: questions.count,
            currentIndex: 1,
            questions: questions,
            selections: [
                "Database": ["SQLite"],
                "Runtime": ["Local"],
            ],
            freeformText: [:]
        )

        XCTAssertTrue(partial.showsSubmit)
        XCTAssertFalse(partial.canSubmit)
        XCTAssertTrue(complete.canSubmit)
    }

    func testConversationContextTrimsEmptyValues() {
        XCTAssertNil(QuestionConversationContext(latestUserPrompt: "  ", agentSummary: "\n"))

        let context = QuestionConversationContext(
            latestUserPrompt: " Build the dashboard ",
            agentSummary: " I need a choice "
        )

        XCTAssertEqual(context?.latestUserPrompt, "Build the dashboard")
        XCTAssertEqual(context?.agentSummary, "I need a choice")
    }

    func testContextFromSessionUsesLatestPromptAndSummary() {
        let session = AgentSession(
            id: "session-1",
            title: "VibePet",
            tool: .claudeCode,
            phase: .waitingForAnswer,
            summary: "Which runtime?",
            updatedAt: Date(timeIntervalSince1970: 1),
            latestUserPrompt: "Add auth"
        )

        XCTAssertEqual(
            QuestionConversationContext(session: session),
            QuestionConversationContext(latestUserPrompt: "Add auth", agentSummary: "Which runtime?")
        )
    }

    func testInteractiveQuestionBodyUsesBoundedScrollArea() {
        XCTAssertLessThanOrEqual(BubbleTheme.interactiveBodyMaxHeight, 280)
        XCTAssertGreaterThan(BubbleTheme.interactiveBodyMaxHeight, BubbleTheme.contentMaxHeight)
    }

    private var questions: [QuestionItem] {
        [
            QuestionItem(
                header: "Database",
                prompt: "Which database should we use?",
                options: [
                    QuestionOption(label: "SQLite", detail: nil, allowsFreeform: false),
                    QuestionOption(label: "Other", detail: nil, allowsFreeform: true),
                ],
                multiSelect: false
            ),
            QuestionItem(
                header: "Runtime",
                prompt: "Where should it run?",
                options: [
                    QuestionOption(label: "Local", detail: nil, allowsFreeform: false),
                    QuestionOption(label: "Cloud", detail: nil, allowsFreeform: false),
                ],
                multiSelect: false
            ),
        ]
    }
}
