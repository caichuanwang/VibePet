import Foundation

/// Normalizes Claude Code hook events into the bridge protocol. M3 covers the
/// notification subset only: `Stop` → `.completion` and `Notification` →
/// `.status`. `PreToolUse` / `AskUserQuestion` parsing and response encoding land
/// in M4 / M5.
public struct ClaudeCodeAdapter: ToolAdapter {
    public let tool: ToolKind = .claudeCode

    /// Reads a displayable summary from a transcript file path, or nil if none.
    /// Injectable so tests can exercise the resolution order without real files.
    private let transcriptSummaryReader: @Sendable (String) -> String?

    /// Used when a `Stop` event carries no displayable summary.
    static let completionFallback = "Claude Code 完成了一轮任务"
    static let notificationFallback = "Claude Code 有新通知"

    public init() {
        self.init(transcriptSummaryReader: ClaudeCodeAdapter.readTranscriptSummary(path:))
    }

    init(transcriptSummaryReader: @escaping @Sendable (String) -> String?) {
        self.transcriptSummaryReader = transcriptSummaryReader
    }

    public func parseEvent(stdin: Data, env: [String: String]) throws -> BridgeEnvelope? {
        guard
            let object = try? JSONSerialization.jsonObject(with: stdin) as? [String: Any],
            let eventName = object["hook_event_name"] as? String
        else {
            return nil
        }

        let source = makeSource(from: object)

        switch eventName {
        case "Stop":
            let summary = resolveCompletionSummary(from: object)
            let isError = (object["is_error"] as? Bool) ?? false
            return makeEnvelope(
                source: source,
                content: .completion(CompletionContent(markdownSummary: summary, isError: isError))
            )
        case "Notification":
            let message = (object["message"] as? String).flatMap(nonEmpty) ?? Self.notificationFallback
            return makeEnvelope(
                source: source,
                content: .status(StatusContent(text: singleLine(message)))
            )
        default:
            // Events outside the M3 notification subset (PreToolUse, AskUserQuestion, …).
            return nil
        }
    }

    public func encodeResponse(_ response: BridgeResponse, for envelope: BridgeEnvelope) -> Data {
        // Notification traffic (M3) never awaits a response. Approval / question
        // response encoding lands in M4 / M5.
        Data()
    }

    // MARK: - Summary resolution

    /// Resolution order: an inline `summary` field, then a transcript excerpt,
    /// then a readable fallback — so a `Stop` event without a displayable summary
    /// still produces meaningful completion text rather than empty content.
    private func resolveCompletionSummary(from object: [String: Any]) -> String {
        if let inline = (object["summary"] as? String).flatMap(nonEmpty) {
            return inline
        }
        if let path = (object["transcript_path"] as? String).flatMap(nonEmpty),
           let fromTranscript = transcriptSummaryReader(path).flatMap(nonEmpty) {
            return fromTranscript
        }
        return Self.completionFallback
    }

    /// Extracts the last assistant text message from a Claude Code transcript
    /// (newline-delimited JSON). Defensive against schema drift: anything it can't
    /// read returns nil so the caller falls back.
    static func readTranscriptSummary(path: String) -> String? {
        guard let contents = try? String(contentsOfFile: path, encoding: .utf8) else {
            return nil
        }

        let lines = contents.split(separator: "\n", omittingEmptySubsequences: true)
        for line in lines.reversed() {
            guard
                let data = line.data(using: .utf8),
                let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                object["type"] as? String == "assistant",
                let message = object["message"] as? [String: Any],
                let content = message["content"] as? [[String: Any]]
            else {
                continue
            }

            let text = content
                .filter { $0["type"] as? String == "text" }
                .compactMap { $0["text"] as? String }
                .joined(separator: "\n")

            if let summary = nonEmpty(text) {
                return summary
            }
        }

        return nil
    }

    // MARK: - Helpers

    private func makeSource(from object: [String: Any]) -> SourceInfo {
        let cwd = (object["cwd"] as? String).flatMap(nonEmpty)
        let projectName = cwd.map { URL(fileURLWithPath: $0).lastPathComponent }
        let sessionShortId = (object["session_id"] as? String)
            .flatMap(nonEmpty)
            .map { String($0.prefix(6)) }

        return SourceInfo(
            tool: .claudeCode,
            projectName: projectName,
            sessionShortId: sessionShortId,
            cwd: cwd
        )
    }

    private func makeEnvelope(source: SourceInfo, content: BubbleContent) -> BridgeEnvelope {
        BridgeEnvelope(requestId: UUID(), source: source, content: content)
    }

    private func singleLine(_ text: String) -> String {
        text
            .split(whereSeparator: \.isNewline)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
    }
}

private func nonEmpty(_ value: String) -> String? {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : value
}
