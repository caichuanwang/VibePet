import Foundation

/// Normalizes Claude Code hook events into the bridge protocol. M3 covered the
/// notification subset (`Stop` → `.completion`, `Notification` → `.status`); M4
/// adds `PreToolUse` (≠ `AskUserQuestion`) → `.approval` parsing and approval
/// response encoding. M5 (spike verified, Claude Code ≥ 2.1.85) adds
/// `AskUserQuestion` → `.question` parsing and answer write-back via `updatedInput`.
public struct ClaudeCodeAdapter: ToolAdapter {
    public let tool: ToolKind = .claudeCode

    /// Reads a displayable summary from a transcript file path, or nil if none.
    /// Injectable so tests can exercise the resolution order without real files.
    private let transcriptSummaryReader: @Sendable (String) -> String?

    /// Tags approval risk from the tool name + command pattern.
    private let riskClassifier: RiskClassifier

    /// Captures a best-effort terminal jump target from hook environment.
    private let terminalJumpCapture: TerminalJumpCapture

    /// Used when a `Stop` event carries no displayable summary.
    static let completionFallback = "Claude Code 完成了一轮任务"
    static let notificationFallback = "Claude Code 有新通知"
    /// Title shown above the structured-question card when `AskUserQuestion` carries
    /// no overall title of its own.
    static let askQuestionTitle = "Claude 需要你确认"
    /// Synthetic free-text choice appended to every question (the CLI adds this
    /// client-side). Selecting it lets the user type a custom answer.
    static let otherOptionLabel = "其他"

    public init() {
        self.init(transcriptSummaryReader: ClaudeCodeAdapter.readTranscriptSummary(path:))
    }

    init(
        transcriptSummaryReader: @escaping @Sendable (String) -> String?,
        riskClassifier: RiskClassifier = RiskClassifier(),
        terminalJumpCapture: TerminalJumpCapture = .live
    ) {
        self.transcriptSummaryReader = transcriptSummaryReader
        self.riskClassifier = riskClassifier
        self.terminalJumpCapture = terminalJumpCapture
    }

    public func parseEvent(stdin: Data, env: [String: String]) throws -> BridgeEnvelope? {
        guard
            let object = try? JSONSerialization.jsonObject(with: stdin) as? [String: Any],
            let eventName = object["hook_event_name"] as? String
        else {
            return nil
        }

        let source = makeSource(from: object, env: env)
        let agentEvent = makeAgentEvent(from: object, source: source)

        switch eventName {
        case "SessionStart", "UserPromptSubmit", "PostToolUse", "SubagentStart", "SubagentStop", "PreCompact", "PermissionDenied", "SessionEnd", "StopFailure":
            guard let agentEvent else { return nil }
            return makeEnvelope(
                source: source,
                content: lifecycleContent(for: eventName, object: object),
                agentEvent: agentEvent
            )
        case "Stop":
            let summary = resolveCompletionSummary(from: object)
            let isError = (object["is_error"] as? Bool) ?? false
            return makeEnvelope(
                source: source,
                content: .completion(CompletionContent(markdownSummary: summary, isError: isError)),
                agentEvent: agentEvent
            )
        case "Notification":
            let message = (object["message"] as? String).flatMap(nonEmpty) ?? Self.notificationFallback
            return makeEnvelope(
                source: source,
                content: .status(StatusContent(text: singleLine(message))),
                agentEvent: agentEvent
            )
        case "PreToolUse":
            if (object["tool_name"] as? String).flatMap(nonEmpty) == "AskUserQuestion" {
                return makeQuestionEnvelope(from: object, source: source, agentEvent: agentEvent)
            }
            return makeApprovalEnvelope(from: object, source: source, agentEvent: agentEvent)
        default:
            // Events outside the supported subset.
            return nil
        }
    }

    public func parseAgentEvent(stdin: Data, env: [String: String]) throws -> AgentEvent? {
        guard let object = try? JSONSerialization.jsonObject(with: stdin) as? [String: Any] else {
            return nil
        }
        return makeAgentEvent(from: object, source: makeSource(from: object, env: env))
    }

    public func encodeResponse(_ response: BridgeResponse, for envelope: BridgeEnvelope) -> Data {
        switch response {
        case let .approval(decision):
            return Self.encodeApproval(decision)
        case let .question(answer):
            return Self.encodeQuestion(answer, for: envelope)
        case .defer:
            // Defer == no JSON on stdout, exit 0 → Claude Code falls back to its
            // normal permission flow (fail-open, §7). Verified against the hooks
            // contract: empty stdout + exit 0 does NOT auto-approve.
            return Data()
        }
    }

    // MARK: - PreToolUse → approval

    /// Builds an `.approval` envelope from a `PreToolUse` event. `AskUserQuestion`
    /// is routed to the question path by the caller, so the guard here is
    /// defensive only.
    private func makeApprovalEnvelope(
        from object: [String: Any],
        source: SourceInfo,
        agentEvent: AgentEvent?
    ) -> BridgeEnvelope? {
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
        return makeEnvelope(source: source, content: .approval(content), agentEvent: agentEvent)
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

    // MARK: - PreToolUse(AskUserQuestion) → question

    /// Builds a `.question` envelope from an `AskUserQuestion` PreToolUse event.
    /// Verified mechanism (M5-0 spike, Claude Code ≥ 2.1.85): a PreToolUse hook can
    /// satisfy `AskUserQuestion` by returning `updatedInput` + `permissionDecision:
    /// "allow"`, so VibePet answers it in-bubble and writes the answer back.
    /// Field names per the `AskUserQuestion` input schema: `questions[].{question,
    /// header, multiSelect, options[].{label, description}}`.
    private func makeQuestionEnvelope(
        from object: [String: Any],
        source: SourceInfo,
        agentEvent: AgentEvent?
    ) -> BridgeEnvelope? {
        guard
            let input = object["tool_input"] as? [String: Any],
            let rawQuestions = input["questions"] as? [[String: Any]]
        else {
            return nil
        }

        let items: [QuestionItem] = rawQuestions.compactMap { question in
            guard let prompt = (question["question"] as? String).flatMap(nonEmpty) else {
                return nil
            }
            let header = (question["header"] as? String).flatMap(nonEmpty) ?? String(prompt.prefix(12))
            let multiSelect = (question["multiSelect"] as? Bool) ?? false
            var options: [QuestionOption] = ((question["options"] as? [[String: Any]]) ?? []).compactMap { option in
                guard let label = (option["label"] as? String).flatMap(nonEmpty) else {
                    return nil
                }
                return QuestionOption(
                    label: label,
                    detail: (option["description"] as? String).flatMap(nonEmpty),
                    allowsFreeform: false
                )
            }
            guard !options.isEmpty else {
                return nil
            }
            // The CLIs add an "Other" free-text choice client-side (and tell the model
            // not to emit one); mirror that so every question can be answered freely.
            // Its typed text becomes the answer value; it is stripped back out before
            // the questions are written into `updatedInput` (see `encodeQuestion`).
            options.append(QuestionOption(label: Self.otherOptionLabel, detail: nil, allowsFreeform: true))
            return QuestionItem(header: header, prompt: prompt, options: options, multiSelect: multiSelect)
        }

        guard !items.isEmpty else {
            return nil
        }
        return makeEnvelope(
            source: source,
            content: .question(QuestionContent(title: Self.askQuestionTitle, questions: items)),
            agentEvent: agentEvent
        )
    }

    // MARK: - Question response encoding

    /// Encodes a question answer to the Claude Code `AskUserQuestion` hook output:
    /// `permissionDecision:"allow"` + an `updatedInput` carrying the original
    /// questions plus the user's answers, so the tool proceeds without prompting
    /// natively (verified ≥ 2.1.85).
    ///
    /// `updatedInput` *replaces* the whole tool input, so `questions` must be
    /// preserved alongside `answers`. `encodeResponse` only sees the normalized
    /// envelope (not the raw stdin), so `questions` are reconstructed from the
    /// `QuestionContent` — minus the synthetic "其他" option, which is a UI-only
    /// affordance that must not leak back into the tool's question schema.
    /// `QuestionAnswer.answers` is keyed by `header`, while the `AskUserQuestion`
    /// `answers` map is keyed by question text — translated here via each
    /// `QuestionItem`. With no usable selection, it defers (no JSON) so the tool
    /// falls back to its native prompt (fail-open).
    static func encodeQuestion(_ answer: QuestionAnswer, for envelope: BridgeEnvelope) -> Data {
        guard case let .question(content) = envelope.content else {
            return Data()
        }

        var answersByQuestion: [String: String] = [:]
        var questions: [[String: Any]] = []
        for item in content.questions {
            if let value = answer.answers[item.header].flatMap(nonEmpty) {
                answersByQuestion[item.prompt] = value
            }
            questions.append([
                "question": item.prompt,
                "header": item.header,
                "multiSelect": item.multiSelect,
                "options": item.options.filter { !$0.allowsFreeform }.map { option -> [String: Any] in
                    var encoded: [String: Any] = ["label": option.label]
                    if let detail = option.detail {
                        encoded["description"] = detail
                    }
                    return encoded
                },
            ])
        }

        guard !answersByQuestion.isEmpty else {
            return Data()
        }

        let payload: [String: Any] = [
            "hookSpecificOutput": [
                "hookEventName": "PreToolUse",
                "permissionDecision": "allow",
                "updatedInput": ["questions": questions, "answers": answersByQuestion],
            ],
        ]
        return (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
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

    private func makeSource(from object: [String: Any], env: [String: String]) -> SourceInfo {
        let cwd = (object["cwd"] as? String).flatMap(nonEmpty)
        let projectName = cwd.map { URL(fileURLWithPath: $0).lastPathComponent }
        let sessionID = (object["session_id"] as? String).flatMap(nonEmpty)
        let sessionShortId = sessionID
            .map { String($0.prefix(6)) }
        let eventName = object["hook_event_name"] as? String

        return SourceInfo(
            tool: .claudeCode,
            projectName: projectName,
            sessionID: sessionID,
            sessionShortId: sessionShortId,
            cwd: cwd,
            jumpTarget: terminalJumpCapture.buildJumpTarget(env: env, cwd: cwd, hookEventName: eventName)
        )
    }

    private func makeEnvelope(
        source: SourceInfo,
        content: BubbleContent,
        agentEvent: AgentEvent? = nil
    ) -> BridgeEnvelope {
        BridgeEnvelope(requestId: UUID(), source: source, content: content, agentEvent: agentEvent)
    }

    private func makeAgentEvent(from object: [String: Any], source: SourceInfo) -> AgentEvent? {
        guard let eventName = object["hook_event_name"] as? String else {
            return nil
        }
        guard let sessionID = (object["session_id"] as? String).flatMap(nonEmpty) else {
            return nil
        }
        let timestamp = Date()

        switch eventName {
        case "SessionStart":
            return .sessionStarted(
                sessionID: sessionID,
                timestamp: timestamp,
                title: source.projectName ?? "Claude Code",
                tool: .claudeCode,
                summary: lifecycleSummary(for: eventName, object: object),
                jumpTarget: source.jumpTarget
            )
        case "UserPromptSubmit", "PostToolUse", "SubagentStart", "SubagentStop", "PreCompact", "Notification":
            return .activityUpdated(
                sessionID: sessionID,
                timestamp: timestamp,
                summary: lifecycleSummary(for: eventName, object: object)
            )
        case "PreToolUse":
            let summary = lifecycleSummary(for: eventName, object: object)
            if (object["tool_name"] as? String).flatMap(nonEmpty) == "AskUserQuestion" {
                return .questionAsked(sessionID: sessionID, timestamp: timestamp, summary: summary)
            }
            return .permissionRequested(sessionID: sessionID, timestamp: timestamp, summary: summary)
        case "Stop":
            return .sessionCompleted(
                sessionID: sessionID,
                timestamp: timestamp,
                summary: resolveCompletionSummary(from: object),
                isError: (object["is_error"] as? Bool) ?? false,
                isSessionEnd: false
            )
        case "StopFailure":
            return .sessionCompleted(
                sessionID: sessionID,
                timestamp: timestamp,
                summary: lifecycleSummary(for: eventName, object: object),
                isError: true,
                isSessionEnd: false
            )
        case "SessionEnd":
            return .sessionCompleted(
                sessionID: sessionID,
                timestamp: timestamp,
                summary: lifecycleSummary(for: eventName, object: object),
                isError: false,
                isSessionEnd: true
            )
        case "PermissionDenied":
            return .actionableStateResolved(
                sessionID: sessionID,
                timestamp: timestamp,
                summary: lifecycleSummary(for: eventName, object: object)
            )
        default:
            return nil
        }
    }

    private func lifecycleContent(for eventName: String, object: [String: Any]) -> BubbleContent {
        if eventName == "StopFailure" {
            return .completion(CompletionContent(markdownSummary: lifecycleSummary(for: eventName, object: object), isError: true))
        }
        if eventName == "SessionEnd" {
            return .completion(CompletionContent(markdownSummary: lifecycleSummary(for: eventName, object: object), isError: false))
        }
        return .status(StatusContent(text: singleLine(lifecycleSummary(for: eventName, object: object))))
    }

    private func lifecycleSummary(for eventName: String, object: [String: Any]) -> String {
        if let message = (object["message"] as? String).flatMap(nonEmpty) {
            return message
        }
        if let summary = (object["summary"] as? String).flatMap(nonEmpty) {
            return summary
        }
        if let prompt = (object["prompt"] as? String).flatMap(nonEmpty) {
            return "User prompt: \(prompt)"
        }
        if let toolName = (object["tool_name"] as? String).flatMap(nonEmpty) {
            return "Claude Code \(eventName): \(toolName)"
        }

        switch eventName {
        case "SessionStart":
            return "Claude Code session started"
        case "UserPromptSubmit":
            return "Claude Code received a prompt"
        case "PostToolUse":
            return "Claude Code finished a tool"
        case "SubagentStart":
            return "Claude Code subagent started"
        case "SubagentStop":
            return "Claude Code subagent stopped"
        case "PreCompact":
            return "Claude Code is compacting context"
        case "PermissionDenied":
            return "Claude Code permission was denied"
        case "SessionEnd":
            return "Claude Code session ended"
        case "StopFailure":
            return "Claude Code stopped with an error"
        default:
            return "Claude Code activity"
        }
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
