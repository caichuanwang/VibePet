import Foundation
import SwiftUI
import VibePetCore

struct QuestionConversationContext: Equatable {
    let latestUserPrompt: String?
    let agentSummary: String?

    init?(latestUserPrompt: String?, agentSummary: String?) {
        let prompt = Self.trim(latestUserPrompt)
        let summary = Self.trim(agentSummary)
        guard prompt != nil || summary != nil else { return nil }
        self.latestUserPrompt = prompt
        self.agentSummary = summary
    }

    init?(session: AgentSession?) {
        guard let session else { return nil }
        self.init(latestUserPrompt: session.latestUserPrompt, agentSummary: session.summary)
    }

    private static func trim(_ value: String?) -> String? {
        let trimmed = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// The interactive structured-question bubble for the `decide` state, used for
/// Claude Code's `AskUserQuestion`. The layout is a faithful port of the question
/// bubble in `docs/bubble-content-redesign.html`: a source header (tool badge +
/// project + meta line) with a blue "Question(s)" status chip, muted user/agent
/// context turns, then a question-first body. A single-question card renders the
/// prompt and its options directly; a multi-question card pages through one
/// `QuestionItem` at a time with a counter, question-kind label, ‹/› controls,
/// progress dots, and an answered-summary strip. Each option is a selectable card
/// (radio for single-select, checkbox for multi-select) showing `label` plus a
/// muted `detail`. Selecting the appended "其他" (`allowsFreeform`) option reveals a
/// dedicated multi-line "我的回答" box below the option list. The footer keeps
/// "回终端" on the left and "稍后" (defer / fail-open) plus the primary
/// submit/next action on the right. Submit (`⌘↩`) collects a `QuestionAnswer`
/// keyed by each item's `header`, with freeform text inlined into the answer value.
/// The card waits for explicit submission; dismissal/fail-open is owned by the
/// surrounding surface and hook runtime.
struct QuestionCard: View {
    struct PagingState: Equatable {
        let currentIndex: Int
        let questionCount: Int
        let canGoPrevious: Bool
        let canGoNext: Bool
        let showsSubmit: Bool
        let canSubmit: Bool
        let currentQuestionComplete: Bool
    }

    let content: QuestionContent
    let source: SourceInfo
    let conversationContext: QuestionConversationContext?
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
    @State private var currentQuestionIndex = 0
    /// Natural height of the scrollable body, measured from its content. Drives the
    /// scroll viewport to size-to-content (so a single question shows all its options
    /// without scrolling) and only scroll once it exceeds `interactiveBodyMaxHeight`.
    @State private var bodyContentHeight: CGFloat = 0

    // MARK: - Palette (mirrors the prototype's blue question accent)

    /// #62b4ff — the question bubble's accent (border, selection, dots, chip).
    private static let accent = Color(red: 98 / 255.0, green: 180 / 255.0, blue: 255 / 255.0)
    /// #bfe1ff — readable text on the blue status chip.
    private static let chipText = Color(red: 191 / 255.0, green: 225 / 255.0, blue: 255 / 255.0)
    /// #ffb04f — Claude's orange tool-mark tint.
    private static let claudeMark = Color(red: 255 / 255.0, green: 176 / 255.0, blue: 79 / 255.0)
    private static let optionRestBackground = Color.white.opacity(0.045)
    private static let optionRestBorder = Color.white.opacity(0.10)
    private static let glyphRestBorder = Color.white.opacity(0.38)
    private static let contextText = Color.white.opacity(0.42)

    static func jumpBack(from source: SourceInfo, onJump: (JumpTarget) -> Void) {
        if let jumpTarget = source.jumpTarget {
            onJump(jumpTarget)
        }
    }

    static func activateBackToTerminal(
        from source: SourceInfo,
        onJump: (JumpTarget) -> Void
    ) -> BridgeResponse? {
        jumpBack(from: source, onJump: onJump)
        return nil
    }

    static func activateSubmit(answer: QuestionAnswer, onAnswer: (BridgeResponse) -> Void) {
        onAnswer(.question(answer))
    }

    static func isQuestionComplete(
        _ item: QuestionItem,
        selections: [String: Set<String>],
        freeformText: [String: String]
    ) -> Bool {
        guard !(selections[item.header]?.isEmpty ?? true) else { return false }
        let chosen = item.options.filter { selections[item.header]?.contains($0.label) ?? false }
        return chosen.allSatisfy { option in
            guard option.allowsFreeform else { return true }
            return !freeformValue(for: item, freeformText: freeformText).isEmpty
        }
    }

    static func hasCompleteSelection(
        questions: [QuestionItem],
        selections: [String: Set<String>],
        freeformText: [String: String]
    ) -> Bool {
        guard !questions.isEmpty else { return false }
        return questions.allSatisfy {
            isQuestionComplete($0, selections: selections, freeformText: freeformText)
        }
    }

    static func pagingState(
        questionCount: Int,
        currentIndex: Int,
        questions: [QuestionItem],
        selections: [String: Set<String>],
        freeformText: [String: String]
    ) -> PagingState {
        let clampedIndex = clampedIndex(currentIndex, count: questionCount)
        let isMultiQuestion = questionCount > 1
        let currentComplete = questions.indices.contains(clampedIndex)
            ? isQuestionComplete(questions[clampedIndex], selections: selections, freeformText: freeformText)
            : false
        let isFinal = questionCount <= 1 || clampedIndex == questionCount - 1
        return PagingState(
            currentIndex: clampedIndex,
            questionCount: questionCount,
            canGoPrevious: isMultiQuestion && clampedIndex > 0,
            canGoNext: isMultiQuestion && clampedIndex < questionCount - 1 && currentComplete,
            showsSubmit: isFinal,
            canSubmit: isFinal && hasCompleteSelection(
                questions: questions,
                selections: selections,
                freeformText: freeformText
            ),
            currentQuestionComplete: currentComplete
        )
    }

    static func nextIndex(
        from currentIndex: Int,
        questions: [QuestionItem],
        selections: [String: Set<String>],
        freeformText: [String: String]
    ) -> Int {
        let state = pagingState(
            questionCount: questions.count,
            currentIndex: currentIndex,
            questions: questions,
            selections: selections,
            freeformText: freeformText
        )
        guard state.canGoNext else { return state.currentIndex }
        return min(state.currentIndex + 1, questions.count - 1)
    }

    static func previousIndex(from currentIndex: Int, questionCount: Int) -> Int {
        max(clampedIndex(currentIndex, count: questionCount) - 1, 0)
    }

    static func selectedLabels(
        for item: QuestionItem,
        selections: [String: Set<String>]
    ) -> Set<String> {
        selections[item.header] ?? []
    }

    static func freeformValue(
        for item: QuestionItem,
        freeformText: [String: String]
    ) -> String {
        (freeformText[item.header] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func clampedIndex(_ index: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return min(max(index, 0), count - 1)
    }

    init(
        content: QuestionContent,
        source: SourceInfo,
        conversationContext: QuestionConversationContext? = nil,
        tailEdge: SpeechBubble.TailEdge = .bottom,
        tailOffsetX: CGFloat = 40,
        presentation: ApprovalPresentation,
        onJump: @escaping (JumpTarget) -> Void = { _ in },
        onAnswer: @escaping (BridgeResponse) -> Void = { _ in }
    ) {
        self.content = content
        self.source = source
        self.conversationContext = conversationContext
        self.tailEdge = tailEdge
        self.tailOffsetX = tailOffsetX
        self.presentation = presentation
        self.onJump = onJump
        self.onAnswer = onAnswer
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, BubbleTheme.padding)
                .padding(.top, BubbleTheme.padding)
                .padding(.bottom, 10)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(BubbleTheme.separator).frame(height: 1)
                }
            ThinBubbleScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    contextView
                    if conversationContext != nil {
                        Divider().overlay(BubbleTheme.separator)
                    }
                    questionBlock
                }
                .padding(.trailing, 8)
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: QuestionBodyHeightKey.self,
                            value: proxy.size.height
                        )
                    }
                )
            }
            // Size the scroll viewport to the content up to the cap. Without a
            // definite height the inner GeometryReader collapses during off-screen
            // `fittingSize` measurement, which is what squeezed the body in the
            // shipped layout; this makes the window hug the real content instead.
            .frame(height: min(max(bodyContentHeight, 1), BubbleTheme.interactiveBodyMaxHeight))
            .onPreferenceChange(QuestionBodyHeightKey.self) { bodyContentHeight = $0 }
            .padding(BubbleTheme.padding)
            footer
        }
        .frame(minWidth: BubbleTheme.minWidth, maxWidth: BubbleTheme.maxWidth, alignment: .leading)
        .background(BubbleTheme.background)
        .clipShape(RoundedRectangle(cornerRadius: BubbleTheme.cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: BubbleTheme.cornerRadius)
                .stroke(Self.accent.opacity(0.48), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.22), radius: 14, y: 8)
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

    // MARK: - Header (source identity + status chip)

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    toolMark
                    Text(projectName)
                        .font(BubbleTheme.bodyFont.weight(.semibold))
                        .foregroundStyle(BubbleTheme.bodyText)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Text(metaLine)
                    .font(BubbleTheme.headerFont)
                    .foregroundStyle(BubbleTheme.mutedText)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)
            statusChip
        }
    }

    private var toolMark: some View {
        Text(toolMarkLetter)
            .font(.system(size: 11, weight: .heavy))
            .frame(width: 18, height: 18)
            .background(toolMarkTint.opacity(source.tool == .claudeCode ? 0.14 : 0.16), in: RoundedRectangle(cornerRadius: 5))
            .foregroundStyle(toolMarkTint)
            .accessibilityHidden(true)
    }

    private var statusChip: some View {
        HStack(spacing: 6) {
            Circle().fill(Self.accent).frame(width: 7, height: 7)
            Text(statusChipTitle)
        }
        .font(BubbleTheme.headerFont)
        .padding(.horizontal, 8)
        .frame(height: 22)
        .background(Self.accent.opacity(0.12), in: Capsule())
        .overlay(Capsule().stroke(Self.accent.opacity(0.38), lineWidth: 1))
        .foregroundStyle(Self.chipText)
        .fixedSize()
        .accessibilityLabel(statusChipTitle)
    }

    private var toolMarkLetter: String {
        switch source.tool {
        case .claudeCode: "A"
        case .codex: "C"
        }
    }

    private var toolMarkTint: Color {
        switch source.tool {
        case .claudeCode: Self.claudeMark
        case .codex: Self.accent
        }
    }

    private var statusChipTitle: String {
        isMultiQuestion ? "Questions · \(content.questions.count)" : "Question"
    }

    private var toolName: String {
        switch source.tool {
        case .claudeCode: "Claude Code"
        case .codex: "Codex"
        }
    }

    private var projectName: String {
        source.projectName.flatMap { $0.isEmpty ? nil : $0 } ?? toolName
    }

    private var metaLine: String {
        var parts = [toolName]
        if let cwd = source.cwd, !cwd.isEmpty {
            parts.append((cwd as NSString).abbreviatingWithTildeInPath)
        }
        if let shortId = source.sessionShortId, !shortId.isEmpty {
            parts.append(shortId.hasPrefix("#") ? shortId : "#\(shortId)")
        }
        return parts.joined(separator: " · ")
    }

    private var sourceLabel: String {
        [toolName, source.projectName, source.sessionShortId]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    // MARK: - Context turns (muted, kept secondary to the question)

    @ViewBuilder
    private var contextView: some View {
        if let conversationContext {
            VStack(alignment: .leading, spacing: 6) {
                if let latestUserPrompt = conversationContext.latestUserPrompt {
                    turnRow(speaker: "用户", text: latestUserPrompt)
                }
                if let agentSummary = conversationContext.agentSummary {
                    turnRow(speaker: "Agent", text: agentSummary)
                }
            }
        }
    }

    private func turnRow(speaker: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Text(speaker)
                .font(BubbleTheme.headerFont)
                .foregroundStyle(Self.contextText)
                .frame(width: 40, alignment: .leading)
            Text(text)
                .font(.caption)
                .foregroundStyle(Self.contextText)
                .lineLimit(2)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(speaker)：\(text)")
    }

    // MARK: - Question block (single page or paged item)

    @ViewBuilder
    private var questionBlock: some View {
        if let item = currentQuestion {
            VStack(alignment: .leading, spacing: 10) {
                if isMultiQuestion {
                    pagerHeader
                    if !answeredSummaries.isEmpty {
                        answeredStrip
                    }
                    questionItemContent(item)
                        .padding(10)
                        .background(Self.optionRestBackground, in: RoundedRectangle(cornerRadius: 7))
                        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Self.optionRestBorder, lineWidth: 1))
                } else {
                    questionItemContent(item)
                }
            }
        }
    }

    private var currentQuestion: QuestionItem? {
        guard !content.questions.isEmpty else { return nil }
        return content.questions[paging.currentIndex]
    }

    private var isMultiQuestion: Bool {
        content.questions.count > 1
    }

    private var paging: PagingState {
        Self.pagingState(
            questionCount: content.questions.count,
            currentIndex: currentQuestionIndex,
            questions: content.questions,
            selections: selections,
            freeformText: freeformText
        )
    }

    @ViewBuilder
    private func questionItemContent(_ item: QuestionItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(item.prompt)
                .font(BubbleTheme.bodyFont.weight(.semibold))
                .foregroundStyle(BubbleTheme.bodyText)
                .fixedSize(horizontal: false, vertical: true)
            if !item.options.isEmpty {
                VStack(spacing: 7) {
                    ForEach(Array(item.options.enumerated()), id: \.offset) { _, option in
                        optionRow(item: item, option: option)
                    }
                }
            }
            if freeformSelected(item) {
                answerBox(for: item)
            }
        }
    }

    // MARK: - Pager (multi-question navigation)

    private var pagerHeader: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("问题 \(paging.currentIndex + 1) / \(content.questions.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.72))
                    .accessibilityLabel("问题 \(paging.currentIndex + 1)，共 \(content.questions.count) 题")
                if !currentKindLabel.isEmpty {
                    Text(currentKindLabel)
                        .font(BubbleTheme.headerFont)
                        .foregroundStyle(Self.contextText)
                }
            }
            Spacer(minLength: 8)
            HStack(spacing: 6) {
                pagerButton(systemName: "chevron.left", enabled: paging.canGoPrevious, label: "上一题", action: goPrevious)
                progressDots
                pagerButton(systemName: "chevron.right", enabled: paging.canGoNext, label: "下一题", action: goNext)
            }
        }
    }

    private func pagerButton(
        systemName: String,
        enabled: Bool,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 28, height: 28)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .background(Color.white.opacity(0.07), in: Circle())
        .overlay(Circle().stroke(Color.white.opacity(0.18), lineWidth: 1))
        .foregroundStyle(enabled ? BubbleTheme.bodyText : BubbleTheme.mutedText.opacity(0.5))
        .disabled(!enabled)
        .accessibilityLabel(label)
    }

    private var progressDots: some View {
        HStack(spacing: 5) {
            ForEach(content.questions.indices, id: \.self) { index in
                Capsule()
                    .fill(dotColor(at: index))
                    .frame(width: index == paging.currentIndex ? 18 : 6, height: 6)
            }
        }
        .accessibilityHidden(true)
    }

    private func dotColor(at index: Int) -> Color {
        if index == paging.currentIndex {
            return Self.accent
        }
        if content.questions.indices.contains(index),
           Self.isQuestionComplete(content.questions[index], selections: selections, freeformText: freeformText) {
            return Self.accent.opacity(0.62)
        }
        return Color.white.opacity(0.2)
    }

    private var currentKindLabel: String {
        guard let item = currentQuestion else { return "" }
        var parts: [String] = []
        if paging.showsSubmit {
            parts.append("最后一题")
        }
        parts.append(item.multiSelect ? "多选" : "单选")
        return parts.joined(separator: " · ")
    }

    // MARK: - Answered summary strip

    private var answeredStrip: some View {
        PillFlowLayout(spacing: 6) {
            ForEach(answeredSummaries, id: \.index) { summary in
                Text("\(summary.index + 1): \(summary.text)")
                    .font(BubbleTheme.headerFont)
                    .foregroundStyle(Color.white.opacity(0.52))
                    .lineLimit(1)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Self.accent.opacity(0.09), in: Capsule())
                    .overlay(Capsule().stroke(Self.accent.opacity(0.16), lineWidth: 1))
            }
        }
        .accessibilityHidden(true)
    }

    /// Completed questions other than the current page, summarized for the strip.
    private var answeredSummaries: [(index: Int, text: String)] {
        guard isMultiQuestion else { return [] }
        return content.questions.enumerated().compactMap { index, item in
            guard index != paging.currentIndex else { return nil }
            guard Self.isQuestionComplete(item, selections: selections, freeformText: freeformText) else { return nil }
            return (index, answerSummaryText(for: item))
        }
    }

    private func answerSummaryText(for item: QuestionItem) -> String {
        let chosen = item.options.filter { selections[item.header]?.contains($0.label) ?? false }
        let values: [String] = chosen.compactMap { option in
            if option.allowsFreeform {
                let text = Self.freeformValue(for: item, freeformText: freeformText)
                return text.isEmpty ? nil : text
            }
            return option.label
        }
        let joined = values.joined(separator: "、")
        return joined.count > 14 ? String(joined.prefix(14)) + "…" : joined
    }

    // MARK: - Options + freeform answer box

    private func optionRow(item: QuestionItem, option: QuestionOption) -> some View {
        let isSelected = selections[item.header]?.contains(option.label) ?? false
        return Button {
            toggle(item: item, option: option)
        } label: {
            HStack(alignment: .top, spacing: 8) {
                optionGlyph(multiSelect: item.multiSelect, isSelected: isSelected)
                VStack(alignment: .leading, spacing: 2) {
                    Text(option.label)
                        .font(BubbleTheme.bodyFont.weight(.semibold))
                        .foregroundStyle(BubbleTheme.bodyText)
                    if let detail = option.detail {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(BubbleTheme.mutedText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 7)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                (isSelected ? Self.accent.opacity(0.09) : Self.optionRestBackground),
                in: RoundedRectangle(cornerRadius: 6)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isSelected ? Self.accent.opacity(0.38) : Self.optionRestBorder, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    @ViewBuilder
    private func optionGlyph(multiSelect: Bool, isSelected: Bool) -> some View {
        ZStack {
            if multiSelect {
                RoundedRectangle(cornerRadius: 4)
                    .stroke(isSelected ? Self.accent : Self.glyphRestBorder, lineWidth: 1)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Self.accent)
                }
            } else {
                Circle()
                    .stroke(isSelected ? Self.accent : Self.glyphRestBorder, lineWidth: 1)
                if isSelected {
                    Circle().fill(Self.accent).padding(3)
                }
            }
        }
        .frame(width: 14, height: 14)
        .padding(.top, 2)
    }

    private func answerBox(for item: QuestionItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("我的回答")
                .font(BubbleTheme.headerFont)
                .foregroundStyle(BubbleTheme.mutedText)
            TextField("填写你的回答…", text: freeformBinding(for: item.header), axis: .vertical)
                .textFieldStyle(.plain)
                .font(BubbleTheme.bodyFont)
                .foregroundStyle(BubbleTheme.bodyText)
                .lineLimit(2 ... 5)
                .padding(8)
                .frame(minHeight: 60, alignment: .topLeading)
                .background(BubbleTheme.fieldBackground, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Self.accent.opacity(0.28), lineWidth: 1))
                .accessibilityLabel("我的回答")
        }
    }

    private func freeformSelected(_ item: QuestionItem) -> Bool {
        item.options.contains { option in
            option.allowsFreeform && (selections[item.header]?.contains(option.label) ?? false)
        }
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

    // MARK: - Footer (terminal + defer + submit/next)

    private var footer: some View {
        BubbleFooter {
            if source.jumpTarget != nil {
                Button("回终端") { handleBackToTerminal() }
                    .buttonStyle(BubbleActionButtonStyle(variant: .neutral))
                    .accessibilityLabel("回终端")
            }
        } trailing: {
            pendingLabel
            Button("稍后") { handleDeferLater() }
                .buttonStyle(BubbleActionButtonStyle(variant: .neutral))
                .accessibilityLabel("稍后回答")
                .accessibilityHint("交还终端原生流程")
            footerPrimaryButton
        }
    }

    @ViewBuilder
    private var footerPrimaryButton: some View {
        if paging.showsSubmit {
            Button(submitTitle) { submit() }
                .keyboardShortcut(.return, modifiers: .command)
                .buttonStyle(BubbleActionButtonStyle(variant: .primary, isEnabled: paging.canSubmit))
                .disabled(!paging.canSubmit)
                .accessibilityLabel(submitTitle)
                .accessibilityHint(paging.canSubmit ? "提交所有问题的答案" : "请先回答所有问题")
        } else {
            Button("下一题") { goNext() }
                .buttonStyle(BubbleActionButtonStyle(variant: .primary, isEnabled: paging.canGoNext))
                .disabled(!paging.canGoNext)
                .accessibilityLabel("下一题")
                .accessibilityHint(paging.canGoNext ? "进入下一题" : "请先回答当前问题")
        }
    }

    private var submitTitle: String {
        isMultiQuestion ? "提交全部回答" : "提交回答"
    }

    /// A muted hint describing how many questions still need a valid answer.
    @ViewBuilder
    private var pendingLabel: some View {
        if let text = pendingHintText {
            Text(text)
                .font(BubbleTheme.headerFont)
                .foregroundStyle(BubbleTheme.mutedText)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    private var pendingHintText: String? {
        if isMultiQuestion {
            let remaining = content.questions.filter {
                !Self.isQuestionComplete($0, selections: selections, freeformText: freeformText)
            }.count
            return remaining == 0 ? "全部已回答，可提交" : "\(remaining) 个问题待回答"
        }
        return hasCompleteSelection ? nil : "需要回答后继续"
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

    private func handleBackToTerminal() {
        _ = Self.activateBackToTerminal(from: source, onJump: onJump)
    }

    private func handleDeferLater() {
        onAnswer(.defer)
    }

    private func goPrevious() {
        currentQuestionIndex = Self.previousIndex(
            from: currentQuestionIndex,
            questionCount: content.questions.count
        )
    }

    private func goNext() {
        currentQuestionIndex = Self.nextIndex(
            from: currentQuestionIndex,
            questions: content.questions,
            selections: selections,
            freeformText: freeformText
        )
    }

    private func submit() {
        guard paging.canSubmit else { return }
        Self.activateSubmit(answer: collectAnswer(), onAnswer: onAnswer)
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
}

/// Carries the question body's natural content height up to the card so the scroll
/// viewport can size to it (and only scroll past `interactiveBodyMaxHeight`).
private struct QuestionBodyHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// A minimal flow layout that wraps its pills onto new rows when they exceed the
/// proposed width — used for the answered-summary strip so it stays bubble-shaped
/// instead of clipping or scrolling.
private struct PillFlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                widest = max(widest, x - spacing)
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        widest = max(widest, x - spacing)
        let width = maxWidth.isFinite ? maxWidth : max(widest, 0)
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        let maxWidth = bounds.width
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(
                at: CGPoint(x: bounds.minX + x, y: bounds.minY + y),
                proposal: ProposedViewSize(size)
            )
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
