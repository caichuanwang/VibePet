import Foundation
import SwiftUI
import VibePetCore

/// The bubble UI for non-interactive notifications (technical design §5.3.1–5.3.2).
/// Renders `.status` (single line) and `.completion` (Markdown, scrolls past ~6
/// lines, error styling). Approval / question rendering lands in M4 / M5.
/// Positioning (quadrant anchoring, tail tracking, clamping) is done by the
/// controller via `BubbleAnchor`; this view draws the bubble and its tail and
/// owns the auto-dismiss timer (hover pauses it).
struct SpeechBubble: View {
    enum TailEdge {
        case top
        case bottom
    }

    struct LayoutProjection: Equatable {
        let sourceLabel: String
        let bodyText: String
        let hasSourceHeader: Bool
        let hasFooter: Bool
        let supportsBodyJumpBack: Bool
        let pausesAutoDismissOnHover: Bool
        let autoDismissSeconds: Double
    }

    let content: BubbleContent
    let source: SourceInfo
    var tailEdge: TailEdge = .bottom
    var tailOffsetX: CGFloat = 40
    var autoDismiss = true
    var onJump: (JumpTarget) -> Void = { _ in }
    var onDismiss: () -> Void = {}

    @State private var hovering = false

    static func jumpBack(from source: SourceInfo, onJump: (JumpTarget) -> Void) {
        if let jumpTarget = source.jumpTarget {
            onJump(jumpTarget)
        }
    }

    nonisolated static func layoutProjection(for content: BubbleContent, source: SourceInfo) -> LayoutProjection {
        LayoutProjection(
            sourceLabel: sourceLabel(for: source),
            bodyText: bodyText(for: content),
            hasSourceHeader: true,
            hasFooter: false,
            supportsBodyJumpBack: source.jumpTarget != nil,
            pausesAutoDismissOnHover: true,
            autoDismissSeconds: autoDismissSeconds(for: content)
        )
    }

    nonisolated static func sourceLabel(for source: SourceInfo) -> String {
        [toolName(for: source.tool), source.projectName, source.sessionShortId]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    nonisolated private static func toolName(for tool: ToolKind) -> String {
        switch tool {
        case .claudeCode: "Claude Code"
        case .codex: "Codex"
        }
    }

    nonisolated private static func bodyText(for content: BubbleContent) -> String {
        switch content {
        case let .status(status): status.text
        case let .completion(completion): completion.markdownSummary
        case .approval, .question: ""
        }
    }

    nonisolated private static func autoDismissSeconds(for content: BubbleContent) -> Double {
        switch content {
        case .status: 7
        case .completion: 9
        case .approval, .question: 20
        }
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
            bodyContent
                .padding(BubbleTheme.padding)
        }
        .frame(minWidth: BubbleTheme.minWidth, maxWidth: BubbleTheme.maxWidth, alignment: .leading)
        .background(BubbleTheme.background)
        .clipShape(RoundedRectangle(cornerRadius: BubbleTheme.cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: BubbleTheme.cornerRadius)
                .stroke(statusAccent.opacity(0.45), lineWidth: 1)
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
        .onHover { hovering = $0 }
        .task { await runAutoDismiss() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    // MARK: - Header (source identity + status chip)

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
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
                    .font(.caption)
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
            .background(toolAccent.opacity(source.tool == .claudeCode ? 0.14 : 0.16), in: RoundedRectangle(cornerRadius: 5))
            .foregroundStyle(toolAccent)
            .accessibilityHidden(true)
    }

    private var statusChip: some View {
        HStack(spacing: 6) {
            Circle().fill(statusAccent).frame(width: 7, height: 7)
            Text(statusTitle)
        }
        .font(BubbleTheme.headerFont)
        .padding(.horizontal, 8)
        .frame(height: 22)
        .background(statusAccent.opacity(0.12), in: Capsule())
        .overlay(Capsule().stroke(statusAccent.opacity(0.38), lineWidth: 1))
        .foregroundStyle(statusChipText)
        .fixedSize()
        .accessibilityHidden(true)
    }

    private var toolMarkLetter: String {
        switch source.tool {
        case .claudeCode: "A"
        case .codex: "C"
        }
    }

    private var toolAccent: Color {
        switch source.tool {
        case .claudeCode: BubbleTheme.accentOrange
        case .codex: BubbleTheme.accentBlue
        }
    }

    /// Status chip + bubble border accent: green while running / done, red on error.
    private var statusAccent: Color {
        switch content {
        case let .completion(completion): completion.isError ? BubbleTheme.accentRed : BubbleTheme.accentGreen
        default: BubbleTheme.accentGreen
        }
    }

    private var statusChipText: Color {
        switch content {
        case let .completion(completion) where completion.isError:
            Color(red: 1, green: 0xd2 / 255, blue: 0xd2 / 255)
        default:
            Color(red: 0xae / 255, green: 1, blue: 0xcd / 255)
        }
    }

    private var statusTitle: String {
        switch content {
        case .status: "运行中"
        case let .completion(completion): completion.isError ? "错误" : "完成"
        case .approval, .question: "运行中"
        }
    }

    private var toolName: String {
        Self.toolName(for: source.tool)
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
        Self.sourceLabel(for: source)
    }

    // MARK: - Body

    @ViewBuilder
    private var bodyContent: some View {
        switch content {
        case let .status(status):
            Text(status.text)
                .font(BubbleTheme.bodyFont)
                .foregroundStyle(BubbleTheme.bodyText)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        case let .completion(completion):
            ThinBubbleScrollView {
                BubbleMarkdownView(
                    markdown: completion.markdownSummary,
                    isError: completion.isError
                )
                .padding(.trailing, 8)
            }
            .frame(maxHeight: BubbleTheme.contentMaxHeight)
        case .approval, .question:
            // Interactive cards land in M4 / M5.
            EmptyView()
        }
    }


    private var accessibilityLabel: String {
        switch content {
        case let .status(status): "\(sourceLabel): \(status.text)"
        case let .completion(completion): "\(sourceLabel): \(completion.markdownSummary)"
        case .approval, .question: sourceLabel
        }
    }

    // MARK: - Auto-dismiss

    private func runAutoDismiss() async {
        guard autoDismiss else {
            return
        }
        var remaining = autoDismissSeconds
        let tick = 0.1
        while remaining > 0 {
            try? await Task.sleep(nanoseconds: UInt64(tick * 1_000_000_000))
            if Task.isCancelled { return }
            if !hovering {
                remaining -= tick
            }
        }
        onDismiss()
    }

    private var autoDismissSeconds: Double {
        Self.autoDismissSeconds(for: content)
    }
}

/// A rounded rectangle with a triangular tail on the pet-facing edge. Shared by
/// `SpeechBubble` and `ApprovalCard`.
struct BubbleShape: Shape {
    let cornerRadius: CGFloat
    let tailEdge: SpeechBubble.TailEdge
    let tailOffsetX: CGFloat
    let tailSize: CGSize

    func path(in rect: CGRect) -> Path {
        Path(roundedRect: rect, cornerRadius: cornerRadius)
    }
}

struct BubbleMarkdownBlock: Equatable {
    enum Kind: Equatable {
        case paragraph
        case bullet
        case numbered(Int)
        case quote
        case code
    }

    let kind: Kind
    let text: String

    static func blocks(from markdown: String) -> [BubbleMarkdownBlock] {
        var blocks: [BubbleMarkdownBlock] = []
        var paragraph: [String] = []
        var codeLines: [String] = []
        var isInCodeFence = false

        func flushParagraph() {
            let text = paragraph.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                blocks.append(BubbleMarkdownBlock(kind: .paragraph, text: text))
            }
            paragraph.removeAll()
        }

        func flushCode() {
            let text = codeLines.joined(separator: "\n").trimmingCharacters(in: .newlines)
            if !text.isEmpty {
                blocks.append(BubbleMarkdownBlock(kind: .code, text: text))
            }
            codeLines.removeAll()
        }

        for line in markdown.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") {
                if isInCodeFence {
                    flushCode()
                } else {
                    flushParagraph()
                }
                isInCodeFence.toggle()
                continue
            }

            if isInCodeFence {
                codeLines.append(line)
                continue
            }

            if trimmed.isEmpty {
                flushParagraph()
                continue
            }

            if let bulletText = Self.unorderedListText(from: trimmed) {
                flushParagraph()
                blocks.append(BubbleMarkdownBlock(kind: .bullet, text: bulletText))
                continue
            }

            if let numbered = Self.numberedListItem(from: trimmed) {
                flushParagraph()
                blocks.append(BubbleMarkdownBlock(kind: .numbered(numbered.index), text: numbered.text))
                continue
            }

            if trimmed.hasPrefix(">") {
                flushParagraph()
                let quoteText = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
                if !quoteText.isEmpty {
                    blocks.append(BubbleMarkdownBlock(kind: .quote, text: quoteText))
                }
                continue
            }

            paragraph.append(trimmed)
        }

        if isInCodeFence {
            flushCode()
        }
        flushParagraph()

        if blocks.isEmpty {
            let fallback = markdown.trimmingCharacters(in: .whitespacesAndNewlines)
            return fallback.isEmpty ? [] : [BubbleMarkdownBlock(kind: .paragraph, text: fallback)]
        }
        return blocks
    }

    private static func unorderedListText(from line: String) -> String? {
        for marker in ["- ", "* ", "+ "] where line.hasPrefix(marker) {
            return String(line.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    private static func numberedListItem(from line: String) -> (index: Int, text: String)? {
        let scanner = Scanner(string: line)
        var index = 0
        guard scanner.scanInt(&index), scanner.scanString(".") != nil || scanner.scanString(")") != nil else {
            return nil
        }
        let text = String(line[scanner.currentIndex...]).trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : (index, text)
    }
}

private struct BubbleMarkdownView: View {
    let markdown: String
    let isError: Bool

    private var blocks: [BubbleMarkdownBlock] {
        BubbleMarkdownBlock.blocks(from: markdown)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func blockView(_ block: BubbleMarkdownBlock) -> some View {
        switch block.kind {
        case .paragraph:
            markdownText(block.text)
        case .bullet:
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("•")
                    .font(BubbleTheme.bodyFont.weight(.semibold))
                    .foregroundStyle(textColor.opacity(0.82))
                markdownText(block.text)
            }
        case let .numbered(index):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(index).")
                    .font(BubbleTheme.bodyFont.monospacedDigit())
                    .foregroundStyle(BubbleTheme.mutedText)
                markdownText(block.text)
            }
        case .quote:
            HStack(alignment: .top, spacing: 7) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(BubbleTheme.border.opacity(0.9))
                    .frame(width: 2)
                markdownText(block.text)
                    .foregroundStyle(textColor.opacity(0.82))
            }
            .padding(.vertical, 1)
        case .code:
            Text(block.text)
                .font(BubbleTheme.monoFont)
                .foregroundStyle(textColor)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: BubbleTheme.innerCornerRadius)
                        .fill(BubbleTheme.fieldBackground)
                )
        }
    }

    private func markdownText(_ string: String) -> Text {
        Text((try? AttributedString(markdown: string)) ?? AttributedString(string))
            .font(BubbleTheme.bodyFont)
            .foregroundStyle(textColor)
    }

    private var textColor: Color {
        isError ? BubbleTheme.errorAccent : BubbleTheme.bodyText
    }
}

struct ThinBubbleScrollView<Content: View>: View {
    private let content: () -> Content
    private let coordinateSpaceName = "thinBubbleScroll"

    @State private var viewportHeight: CGFloat = 1
    @State private var contentHeight: CGFloat = 1
    @State private var contentMinY: CGFloat = 0

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    private var trackHeight: CGFloat {
        max(viewportHeight - 2, 1)
    }

    private var thumbHeight: CGFloat {
        guard contentHeight > viewportHeight else { return trackHeight }
        return min(trackHeight, max(18, trackHeight * viewportHeight / contentHeight))
    }

    private var thumbOffset: CGFloat {
        let maxScroll = max(contentHeight - viewportHeight, 1)
        let scrollOffset = min(max(-contentMinY, 0), maxScroll)
        return scrollOffset / maxScroll * max(trackHeight - thumbHeight, 0)
    }

    var body: some View {
        GeometryReader { viewport in
            ZStack(alignment: .trailing) {
                ScrollView(.vertical, showsIndicators: false) {
                    content()
                        .background(
                            GeometryReader { contentProxy in
                                Color.clear.preference(
                                    key: ThinBubbleScrollMetricsKey.self,
                                    value: ThinBubbleScrollMetrics(
                                        height: contentProxy.size.height,
                                        minY: contentProxy.frame(in: .named(coordinateSpaceName)).minY
                                    )
                                )
                            }
                        )
                }
                .coordinateSpace(name: coordinateSpaceName)
                .onAppear {
                    viewportHeight = max(viewport.size.height, 1)
                }
                .onChange(of: viewport.size.height) { _, height in
                    viewportHeight = max(height, 1)
                }
                .onPreferenceChange(ThinBubbleScrollMetricsKey.self) { metrics in
                    contentHeight = max(metrics.height, 1)
                    contentMinY = metrics.minY
                }

                if contentHeight > viewportHeight + 1 {
                    VStack {
                        Capsule()
                            .fill(BubbleTheme.mutedText.opacity(0.38))
                            .frame(width: BubbleTheme.scrollThumbWidth, height: thumbHeight)
                            .offset(y: thumbOffset)
                        Spacer(minLength: 0)
                    }
                    .frame(width: BubbleTheme.scrollThumbWidth, height: trackHeight, alignment: .top)
                    .padding(.vertical, 1)
                    .allowsHitTesting(false)
                }
            }
        }
    }
}

private struct ThinBubbleScrollMetrics: Equatable {
    let height: CGFloat
    let minY: CGFloat
}

private struct ThinBubbleScrollMetricsKey: PreferenceKey {
    static let defaultValue = ThinBubbleScrollMetrics(height: 1, minY: 0)

    static func reduce(value: inout ThinBubbleScrollMetrics, nextValue: () -> ThinBubbleScrollMetrics) {
        value = nextValue()
    }
}
