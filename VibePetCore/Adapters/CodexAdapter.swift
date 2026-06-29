import Foundation

/// Normalizes Codex events into the bridge protocol (technical design §4.2).
///
/// Two delivery surfaces, both arriving here as `Data`:
/// - **`PermissionRequest` hook** (JSON on stdin): shell escalation → `.command`,
///   `apply_patch` → `.fileChange`, risk-classified, binary allow/deny. An
///   answer-requiring request (Codex hooks cannot fill answers back — `updatedInput`
///   "fails closed") downgrades to `.approval(requiresTerminalApproval: true)`.
/// - **`notify` program** (`agent-turn-complete`, JSON passed as argv by Codex):
///   → `.completion`.
///
/// Response encoding (`PermissionRequest` only): allow / deny carry
/// `hookSpecificOutput.decision.behavior`; `question`/`defer` **decline** by
/// emitting no output, which Codex treats as "use the native approval flow"
/// (fail-open). `allowAlways` has no verified Codex persistent rule, so it equals
/// a one-time allow. Encoding is deterministic and never embeds `requestId` — Codex
/// loads multiple matching hooks and may run them concurrently, so VibePet must not
/// assume it owns the decision; `requestId` is only for VibePet's own pairing.
public struct CodexAdapter: ToolAdapter {
    public let tool: ToolKind = .codex

    private let riskClassifier: RiskClassifier
    private let terminalJumpCapture: TerminalJumpCapture

    static let completionFallback = "Codex 完成了一轮任务"
    static let terminalApprovalTitle = "需在终端处理"
    /// Tool names whose request needs free-form user input rather than a binary
    /// allow/deny. Provisional: mirrors Claude's `AskUserQuestion` name pending a
    /// real Codex session (see `Tests/Fixtures/codex/codex-spike-notes.md`).
    static let freeformInputTools: Set<String> = ["AskUserQuestion"]

    public init() {
        self.init(riskClassifier: RiskClassifier())
    }

    init(
        riskClassifier: RiskClassifier = RiskClassifier(),
        terminalJumpCapture: TerminalJumpCapture = .live
    ) {
        self.riskClassifier = riskClassifier
        self.terminalJumpCapture = terminalJumpCapture
    }

    public func parseEvent(stdin: Data, env: [String: String]) throws -> BridgeEnvelope? {
        guard let object = try? JSONSerialization.jsonObject(with: stdin) as? [String: Any] else {
            return nil
        }

        // `notify` program payload (delivered via argv, fed in as Data by the CLI).
        // VibePet installs the `Stop` hook instead, but notify is still parsed for
        // robustness if a user wires it up.
        if (object["type"] as? String) == "agent-turn-complete" {
            let source = makeSource(from: object, env: env, sessionKeys: ["session_id", "thread-id", "thread_id", "turn-id"])
            return makeCompletionEnvelope(
                summary: (object["last-assistant-message"] as? String).flatMap(nonEmpty),
                source: source,
                agentEvent: makeCompletionEvent(from: object, source: source)
            )
        }

        guard let event = object["hook_event_name"] as? String else {
            return nil
        }
        switch event {
        case "PermissionRequest":
            return makePermissionEnvelope(from: object, env: env)
        case "Stop":
            // Turn-completion: VibePet registers a Codex `Stop` hook (open-vibe-island
            // pattern) and shows the last assistant message as a completion.
            let source = makeSource(from: object, env: env)
            return makeCompletionEnvelope(
                summary: (object["last_assistant_message"] as? String).flatMap(nonEmpty),
                source: source,
                agentEvent: makeAgentEvent(from: object, source: source)
            )
        case "SessionStart", "UserPromptSubmit":
            let source = makeSource(from: object, env: env)
            guard let agentEvent = makeAgentEvent(from: object, source: source) else { return nil }
            return makeEnvelope(
                source: source,
                content: .status(StatusContent(text: lifecycleSummary(for: event, object: object))),
                agentEvent: agentEvent
            )
        default:
            // Other lifecycle hooks are outside the MVP subset.
            return nil
        }
    }

    public func parseAgentEvent(stdin: Data, env: [String: String]) throws -> AgentEvent? {
        guard let object = try? JSONSerialization.jsonObject(with: stdin) as? [String: Any] else {
            return nil
        }
        if (object["type"] as? String) == "agent-turn-complete" {
            let source = makeSource(from: object, env: env, sessionKeys: ["session_id", "thread-id", "thread_id", "turn-id"])
            return makeCompletionEvent(from: object, source: source)
        }
        if (object["hook_event_name"] as? String) == "PostToolUse" {
            return nil
        }
        return makeAgentEvent(from: object, source: makeSource(from: object, env: env))
    }

    public func encodeResponse(_ response: BridgeResponse, for envelope: BridgeEnvelope) -> Data {
        switch response {
        case let .approval(decision):
            return Self.encodeDecision(decision)
        case .question, .defer:
            // Decline: emit nothing. Codex treats no output (and any non-JSON) as
            // "no decision" and falls back to its native approval flow (§4.2).
            // `question` cannot be answered through a Codex hook, so it declines too.
            return Data()
        }
    }

    // MARK: - PermissionRequest → approval

    private func makePermissionEnvelope(from object: [String: Any], env: [String: String]) -> BridgeEnvelope? {
        guard let toolName = (object["tool_name"] as? String).flatMap(nonEmpty) else {
            return nil
        }
        let source = makeSource(from: object, env: env)
        let agentEvent = makeAgentEvent(from: object, source: source)
        let input = object["tool_input"] as? [String: Any] ?? [:]

        if Self.freeformInputTools.contains(toolName) {
            let summary = (input["description"] as? String).flatMap(nonEmpty) ?? toolName
            let content = ApprovalContent(
                title: Self.terminalApprovalTitle,
                risk: .medium,
                preview: .generic(summary: summary),
                alwaysAllow: nil,
                requiresTerminalApproval: true
            )
            return makeEnvelope(source: source, content: .approval(content), agentEvent: agentEvent)
        }

        let preview = Self.actionPreview(toolName: toolName, input: input)
        let command = Self.isShellTool(toolName) ? (input["command"] as? String) : nil
        let risk = riskClassifier.classify(toolName: toolName, command: command)
        let content = ApprovalContent(
            title: Self.approvalTitle(toolName: toolName),
            risk: risk,
            preview: preview,
            // Codex persistent allow rules are unverified → no "always allow" option.
            alwaysAllow: nil,
            requiresTerminalApproval: false
        )
        return makeEnvelope(source: source, content: .approval(content), agentEvent: agentEvent)
    }

    private static func isShellTool(_ toolName: String) -> Bool {
        toolName == "Bash" || toolName == "shell"
    }

    /// Builds an `ActionPreview` from a Codex `PermissionRequest`'s `tool_input`.
    /// Shell tools carry `command`; `apply_patch` carries a patch envelope in
    /// `command`; anything else (e.g. an MCP tool) is shown generically.
    static func actionPreview(toolName: String, input: [String: Any]) -> ActionPreview {
        if isShellTool(toolName) {
            return .command(text: (input["command"] as? String) ?? "")
        }
        if toolName == "apply_patch" {
            return parseApplyPatch((input["command"] as? String) ?? "")
        }
        return .generic(summary: toolName)
    }

    static func approvalTitle(toolName: String) -> String {
        if isShellTool(toolName) {
            return "运行命令"
        }
        if toolName == "apply_patch" {
            return "修改文件"
        }
        return "请求执行 \(toolName)"
    }

    /// Lightweight parse of a Codex apply_patch envelope: the first target path and
    /// added/removed line counts. Patch headers (`*** …`, `@@`) don't start with
    /// `+`/`-`, so counting content lines by their leading character is sufficient.
    static func parseApplyPatch(_ patch: String) -> ActionPreview {
        let markers = ["*** Update File: ", "*** Add File: ", "*** Delete File: ", "*** Move to: "]
        var path = ""
        var added = 0
        var removed = 0
        for rawLine in patch.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            if path.isEmpty {
                for marker in markers where line.hasPrefix(marker) {
                    path = String(line.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces)
                    break
                }
            }
            if line.hasPrefix("+") && !line.hasPrefix("+++") {
                added += 1
            } else if line.hasPrefix("-") && !line.hasPrefix("---") {
                removed += 1
            }
        }
        return .fileChange(path: path, added: added, removed: removed)
    }

    // MARK: - completion (Stop hook / notify)

    private func makeCompletionEnvelope(
        summary: String?,
        source: SourceInfo,
        agentEvent: AgentEvent?
    ) -> BridgeEnvelope {
        makeEnvelope(
            source: source,
            content: .completion(CompletionContent(markdownSummary: summary ?? Self.completionFallback, isError: false)),
            agentEvent: agentEvent
        )
    }

    // MARK: - Response encoding

    static func encodeDecision(_ decision: ApprovalDecision) -> Data {
        switch decision {
        case .allowOnce, .allowAlways:
            return decisionJSON(behavior: "allow", message: nil)
        case let .deny(reason):
            return decisionJSON(behavior: "deny", message: reason.flatMap(nonEmpty) ?? defaultDenyMessage)
        }
    }

    static let defaultDenyMessage = "VibePet：用户拒绝了此操作"

    private static func decisionJSON(behavior: String, message: String?) -> Data {
        var decision: [String: Any] = ["behavior": behavior]
        if let message {
            decision["message"] = message
        }
        let payload: [String: Any] = [
            "hookSpecificOutput": [
                "hookEventName": "PermissionRequest",
                "decision": decision,
            ],
        ]
        return (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
    }

    // MARK: - Helpers

    private func makeSource(
        from object: [String: Any],
        env: [String: String],
        sessionKeys: [String] = ["session_id"]
    ) -> SourceInfo {
        let cwd = (object["cwd"] as? String).flatMap(nonEmpty)
        let projectName = cwd.map { URL(fileURLWithPath: $0).lastPathComponent }
        let sessionID = sessionKeys
            .lazy
            .compactMap { (object[$0] as? String).flatMap(nonEmpty) }
            .first
        let sessionShortId = sessionID
            .map { String($0.prefix(6)) }
        let eventName = object["hook_event_name"] as? String

        return SourceInfo(
            tool: .codex,
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
        guard
            let event = object["hook_event_name"] as? String,
            let sessionID = (object["session_id"] as? String).flatMap(nonEmpty)
        else {
            return nil
        }
        let timestamp = Date()

        switch event {
        case "SessionStart":
            return .sessionStarted(
                sessionID: sessionID,
                timestamp: timestamp,
                title: source.projectName ?? "Codex",
                tool: .codex,
                summary: lifecycleSummary(for: event, object: object),
                jumpTarget: source.jumpTarget
            )
        case "UserPromptSubmit":
            return .activityUpdated(
                sessionID: sessionID,
                timestamp: timestamp,
                summary: lifecycleSummary(for: event, object: object)
            )
        case "PermissionRequest":
            return .permissionRequested(
                sessionID: sessionID,
                timestamp: timestamp,
                summary: lifecycleSummary(for: event, object: object)
            )
        case "Stop":
            return .sessionCompleted(
                sessionID: sessionID,
                timestamp: timestamp,
                summary: (object["last_assistant_message"] as? String).flatMap(nonEmpty) ?? Self.completionFallback,
                isError: (object["is_error"] as? Bool) ?? false,
                isSessionEnd: false
            )
        default:
            return nil
        }
    }

    private func makeCompletionEvent(from object: [String: Any], source: SourceInfo) -> AgentEvent? {
        let keys = ["session_id", "thread-id", "thread_id", "turn-id"]
        guard let sessionID = keys.lazy.compactMap({ (object[$0] as? String).flatMap(nonEmpty) }).first else {
            return nil
        }
        return .sessionCompleted(
            sessionID: sessionID,
            timestamp: Date(),
            summary: (object["last-assistant-message"] as? String).flatMap(nonEmpty) ?? Self.completionFallback,
            isError: false,
            isSessionEnd: false
        )
    }

    private func lifecycleSummary(for event: String, object: [String: Any]) -> String {
        if let prompt = (object["prompt"] as? String).flatMap(nonEmpty) {
            return "User prompt: \(prompt)"
        }
        if let toolName = (object["tool_name"] as? String).flatMap(nonEmpty) {
            return "Codex \(event): \(toolName)"
        }
        if let message = (object["message"] as? String).flatMap(nonEmpty) {
            return message
        }
        switch event {
        case "SessionStart":
            return "Codex session started"
        case "UserPromptSubmit":
            return "Codex received a prompt"
        case "PermissionRequest":
            return "Codex needs approval"
        default:
            return "Codex activity"
        }
    }
}

private func nonEmpty(_ value: String) -> String? {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : value
}
