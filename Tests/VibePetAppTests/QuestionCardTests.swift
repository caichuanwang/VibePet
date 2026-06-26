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
