import SwiftUI
import VibePetCore

/// The interactive structured-question bubble for the `decide` state (technical
/// design §5.3.4), used for Claude Code's `AskUserQuestion`. Renders each
/// `QuestionItem` with radio (single-select) or checkbox (multi-select) options,
/// each showing `label` + a muted `detail` line; the appended "其他" (`allowsFreeform`)
/// option reveals a text field when selected. Submit (`⌘↩`) collects a `QuestionAnswer`
/// keyed by each item's `header`, freeform text inlined into the answer value. The
/// card waits for explicit submission; dismissal/fail-open is owned by the surrounding
/// surface and hook runtime.
struct QuestionCard: View {
    let content: QuestionContent
    let source: SourceInfo
    var tailEdge: SpeechBubble.TailEdge = .bottom
    var tailOffsetX: CGFloat = 40
    var onJump: (JumpTarget) -> Void = { _ in }
    var onAnswer: (BridgeResponse) -> Void = { _ in }

    @ObservedObject var presentation: ApprovalPresentation
    /// header → selected option labels (a set so multi-select is uniform; single
    /// select keeps at most one).
    @State private var selections: [String: Set<String>] = [:]
    /// header → free-text entered for a selected `allowsFreeform` option.
    @State private var freeformText: [String: String] = [:]

    static func jumpBack(from source: SourceInfo, onJump: (JumpTarget) -> Void) {
        if let jumpTarget = source.jumpTarget {
            onJump(jumpTarget)
        }
    }

    static func hasCompleteSelection(
        questions: [QuestionItem],
        selections: [String: Set<String>],
        freeformText: [String: String]
    ) -> Bool {
        guard !questions.isEmpty else { return false }
        return questions.allSatisfy { item in
            guard !(selections[item.header]?.isEmpty ?? true) else { return false }
            let chosen = item.options.filter { selections[item.header]?.contains($0.label) ?? false }
            return chosen.allSatisfy { option in
                guard option.allowsFreeform else { return true }
                return !(freeformText[item.header] ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .isEmpty
            }
        }
    }

    init(
        content: QuestionContent,
        source: SourceInfo,
        tailEdge: SpeechBubble.TailEdge = .bottom,
        tailOffsetX: CGFloat = 40,
        presentation: ApprovalPresentation,
        onJump: @escaping (JumpTarget) -> Void = { _ in },
        onAnswer: @escaping (BridgeResponse) -> Void = { _ in }
    ) {
        self.content = content
        self.source = source
        self.tailEdge = tailEdge
        self.tailOffsetX = tailOffsetX
        self.presentation = presentation
        self.onJump = onJump
        self.onAnswer = onAnswer
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            Divider().overlay(BubbleTheme.separator)
            questionsBody
            footer
        }
        .padding(BubbleTheme.padding)
        .frame(minWidth: BubbleTheme.minWidth, maxWidth: BubbleTheme.maxWidth, alignment: .leading)
        .background(bubbleBackground)
        .contentShape(
            BubbleShape(
                cornerRadius: BubbleTheme.cornerRadius,
                tailEdge: tailEdge,
                tailOffsetX: tailOffsetX,
                tailSize: BubbleTheme.tailSize
            )
        )
        .onTapGesture(count: 2) {
            Self.jumpBack(from: source, onJump: onJump)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(sourceLabel)：\(content.title)")
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: toolIcon)
            Text(sourceLabel)
                .lineLimit(1)
            Spacer(minLength: 6)
        }
        .font(BubbleTheme.headerFont)
        .foregroundStyle(BubbleTheme.headerText)
    }

    private var toolIcon: String {
        switch source.tool {
        case .claudeCode: "sparkles"
        case .codex: "terminal"
        }
    }

    private var toolName: String {
        switch source.tool {
        case .claudeCode: "Claude Code"
        case .codex: "Codex"
        }
    }

    private var sourceLabel: String {
        [toolName, source.projectName, source.sessionShortId]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    // MARK: - Body (questions)

    private var questionsBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !content.title.isEmpty {
                Text(content.title)
                    .font(BubbleTheme.bodyFont.weight(.semibold))
                    .foregroundStyle(BubbleTheme.bodyText)
            }
            ForEach(Array(content.questions.enumerated()), id: \.offset) { _, item in
                questionView(item)
            }
        }
    }

    @ViewBuilder
    private func questionView(_ item: QuestionItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.prompt)
                .font(BubbleTheme.bodyFont.weight(.medium))
                .foregroundStyle(BubbleTheme.bodyText)
            ForEach(Array(item.options.enumerated()), id: \.offset) { _, option in
                optionRow(item: item, option: option)
            }
        }
    }

    @ViewBuilder
    private func optionRow(item: QuestionItem, option: QuestionOption) -> some View {
        let isSelected = selections[item.header]?.contains(option.label) ?? false
        VStack(alignment: .leading, spacing: 2) {
            Button {
                toggle(item: item, option: option)
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: selectionSymbol(multiSelect: item.multiSelect, isSelected: isSelected))
                        .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(option.label)
                            .foregroundStyle(BubbleTheme.bodyText)
                        if let detail = option.detail {
                            Text(detail)
                                .font(.caption)
                                .foregroundStyle(BubbleTheme.mutedText)
                        }
                    }
                }
            }
            .buttonStyle(.plain)

            if isSelected, option.allowsFreeform {
                TextField("填写…", text: freeformBinding(for: item.header))
                    .textFieldStyle(.roundedBorder)
                    .font(BubbleTheme.bodyFont)
                    .padding(.leading, 24)
            }
        }
    }

    private func selectionSymbol(multiSelect: Bool, isSelected: Bool) -> String {
        if multiSelect {
            return isSelected ? "checkmark.square.fill" : "square"
        }
        return isSelected ? "largecircle.fill.circle" : "circle"
    }

    private func toggle(item: QuestionItem, option: QuestionOption) {
        var current = selections[item.header] ?? []
        if item.multiSelect {
            if current.contains(option.label) {
                current.remove(option.label)
            } else {
                current.insert(option.label)
            }
        } else {
            // Single-select: a tap replaces any prior choice.
            current = [option.label]
        }
        selections[item.header] = current
    }

    private func freeformBinding(for header: String) -> Binding<String> {
        Binding(
            get: { freeformText[header] ?? "" },
            set: { freeformText[header] = $0 }
        )
    }

    // MARK: - Footer (submit)

    private var footer: some View {
        HStack(spacing: 8) {
            pendingLabel
            Spacer(minLength: 6)
            Button("提交") { submit() }
                .keyboardShortcut(.return, modifiers: .command)
                .buttonStyle(.borderedProminent)
                .disabled(!hasCompleteSelection)
        }
        .font(.callout)
    }

    @ViewBuilder
    private var pendingLabel: some View {
        if presentation.pendingCount > 0 {
            Text("还有 \(presentation.pendingCount) 个待处理")
                .font(.caption2)
                .foregroundStyle(BubbleTheme.mutedText)
        }
    }

    /// Submit is enabled only when every question yields a usable value: at least
    /// one option chosen, and any chosen freeform ("其他") option has non-empty text.
    private var hasCompleteSelection: Bool {
        Self.hasCompleteSelection(
            questions: content.questions,
            selections: selections,
            freeformText: freeformText
        )
    }

    private func submit() {
        onAnswer(.question(collectAnswer()))
    }

    /// Collects selections into a `QuestionAnswer` keyed by each item's `header`,
    /// with one string value per answered question: options are taken in display
    /// order; a freeform ("其他") choice contributes the user's typed text in place
    /// of its label; the values are joined with `", "` (single-select yields one).
    /// This mirrors how Claude Code's CLI inlines free text into the answer value.
    private func collectAnswer() -> QuestionAnswer {
        var answers: [String: String] = [:]
        for item in content.questions {
            let chosen = item.options.filter { selections[item.header]?.contains($0.label) ?? false }
            let values: [String] = chosen.compactMap { option in
                if option.allowsFreeform {
                    let text = trimmedFreeform(item.header)
                    return text.isEmpty ? nil : text
                }
                return option.label
            }
            if !values.isEmpty {
                answers[item.header] = values.joined(separator: ", ")
            }
        }
        return QuestionAnswer(answers: answers)
    }

    private func trimmedFreeform(_ header: String) -> String {
        (freeformText[header] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Background + tail

    private var bubbleBackground: some View {
        BubbleShape(
            cornerRadius: BubbleTheme.cornerRadius,
            tailEdge: tailEdge,
            tailOffsetX: tailOffsetX,
            tailSize: BubbleTheme.tailSize
        )
        .fill(BubbleTheme.background)
        .shadow(color: Color.black.opacity(0.22), radius: 14, y: 8)
        .overlay(
            BubbleShape(
                cornerRadius: BubbleTheme.cornerRadius,
                tailEdge: tailEdge,
                tailOffsetX: tailOffsetX,
                tailSize: BubbleTheme.tailSize
            )
            .stroke(BubbleTheme.border, lineWidth: 1)
        )
    }
}
