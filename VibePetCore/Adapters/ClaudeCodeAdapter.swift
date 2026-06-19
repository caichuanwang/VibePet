import Foundation

/// Normalizes Claude Code hook events into the bridge protocol. M3 covered the
/// notification subset (`Stop` → `.completion`, `Notification` → `.status`); M4
/// adds `PreToolUse` (≠ `AskUserQuestion`) → `.approval` parsing and approval
/// response encoding. `AskUserQuestion` → `.question` lands in M5.
public struct ClaudeCodeAdapter: ToolAdapter {
    public let tool: ToolKind = .claudeCode

    /// Reads a displayable summary from a transcript file path, or nil if none.
    /// Injectable so tests can exercise the resolution order without real files.
    private let transcriptSummaryReader: @Sendable (String) -> String?

    /// Tags approval risk from the tool name + command pattern.
    private let riskClassifier: RiskClassifier

    /// Used when a `Stop` event carries no displayable summary.
    static let completionFallback = "Claude Code 完成了一轮任务"
    static let notificationFallback = "Claude Code 有新通知"

    public init() {
        self.init(transcriptSummaryReader: ClaudeCodeAdapter.readTranscriptSummary(path:))
    }

    init(
        transcriptSummaryReader: @escaping @Sendable (String) -> String?,
        riskClassifier: RiskClassifier = RiskClassifier()
    ) {
        self.transcriptSummaryReader = transcriptSummaryReader
        self.riskClassifier = riskClassifier
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
        case "PreToolUse":
            return makeApprovalEnvelope(from: object, source: source)
        default:
            // Events outside the supported subset.
            return nil
        }
    }

    public func encodeResponse(_ response: BridgeResponse, for envelope: BridgeEnvelope) -> Data {
        switch response {
        case let .approval(decision):
            return Self.encodeApproval(decision)
        case .question:
            // Question (`updatedInput`) encoding lands in M5.
            return Data()
        case .defer:
            // Defer == no JSON on stdout, exit 0 → Claude Code falls back to its
            // normal permission flow (fail-open, §7). Verified against the hooks
            // contract: empty stdout + exit 0 does NOT auto-approve.
            return Data()
        }
    }

    // MARK: - PreToolUse → approval

    /// Builds an `.approval` envelope from a `PreToolUse` event. `AskUserQuestion`
    /// is a question (M5), not an approval, so it is ignored here.
    private func makeApprovalEnvelope(from object: [String: Any], source: SourceInfo) -> BridgeEnvelope? {
        guard let toolName = (object["tool_name"] as? String).flatMap(nonEmpty) else {
            return nil
        }
        guard toolName != "AskUserQuestion" else {
            return nil
        }

        let input = object["tool_input"] as? [String: Any] ?? [:]
        let preview = Self.actionPreview(toolName: toolName, input: input)
        // Only Bash carries a shell command to pattern-match for risk.
        let command = (toolName == "Bash") ? (input["command"] as? String) : nil
        let risk = riskClassifier.classify(toolName: toolName, command: command)

        let content = ApprovalContent(
            title: Self.approvalTitle(toolName: toolName),
            risk: risk,
            preview: preview,
            // PreToolUse cannot grant a persistent allow (M4-3a spike: unsupported);
            // leave `alwaysAllow` nil so the UI hides "始终允许".
            alwaysAllow: nil,
            requiresTerminalApproval: false
        )
        return makeEnvelope(source: source, content: .approval(content))
    }

    /// Assembles an `ActionPreview` from a tool's `tool_input` (verified field
    /// names per the Claude Code tools contract).
    static func actionPreview(toolName: String, input: [String: Any]) -> ActionPreview {
        switch toolName {
        case "Bash":
            return .command(text: (input["command"] as? String) ?? "")
        case "Edit":
            return .fileChange(
                path: (input["file_path"] as? String) ?? "",
                added: lineCount(input["new_string"] as? String),
                removed: lineCount(input["old_string"] as? String)
            )
        case "Write":
            return .fileChange(
                path: (input["file_path"] as? String) ?? "",
                added: lineCount(input["content"] as? String),
                removed: 0
            )
        case "Read":
            return .fileRead(path: (input["file_path"] as? String) ?? "")
        case "WebFetch":
            return .network(target: (input["url"] as? String) ?? "")
        default:
            return .generic(summary: toolName)
        }
    }

    static func approvalTitle(toolName: String) -> String {
        switch toolName {
        case "Bash":
            return "运行命令"
        case "Edit", "Write":
            return "修改文件"
        case "Read":
            return "读取文件"
        case "WebFetch":
            return "访问网络"
        default:
            return "请求执行 \(toolName)"
        }
    }

    private static func lineCount(_ text: String?) -> Int {
        guard let text, !text.isEmpty else { return 0 }
        return text.split(separator: "\n", omittingEmptySubsequences: false).count
    }

    // MARK: - Approval response encoding

    /// Encodes an approval decision to the Claude Code `PreToolUse` hook output.
    /// `allowAlways` cannot be persisted via this hook (M4-3a), so it degrades to a
    /// one-time allow; the UI hides the button when `alwaysAllow` is nil, making
    /// that path defensive only.
    static func encodeApproval(_ decision: ApprovalDecision) -> Data {
        switch decision {
        case let .deny(reason):
            return permissionDecisionJSON(decision: "deny", reason: reason)
        case .allowOnce:
            return permissionDecisionJSON(decision: "allow", reason: nil)
        case .allowAlways:
            return permissionDecisionJSON(decision: "allow", reason: nil)
        }
    }

    private static func permissionDecisionJSON(decision: String, reason: String?) -> Data {
        var hookOutput: [String: Any] = [
            "hookEventName": "PreToolUse",
            "permissionDecision": decision,
        ]
        if let reason = reason.flatMap(nonEmpty) {
            hookOutput["permissionDecisionReason"] = reason
        }
        let payload: [String: Any] = ["hookSpecificOutput": hookOutput]
        return (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
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
