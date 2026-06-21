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

    static let completionFallback = "Codex 完成了一轮任务"
    static let terminalApprovalTitle = "需在终端处理"
    /// Tool names whose request needs free-form user input rather than a binary
    /// allow/deny. Provisional: mirrors Claude's `AskUserQuestion` name pending a
    /// real Codex session (see `Tests/Fixtures/codex/codex-spike-notes.md`).
    static let freeformInputTools: Set<String> = ["AskUserQuestion"]

    public init() {
        self.init(riskClassifier: RiskClassifier())
    }

    init(riskClassifier: RiskClassifier = RiskClassifier()) {
        self.riskClassifier = riskClassifier
    }

    public func parseEvent(stdin: Data, env: [String: String]) throws -> BridgeEnvelope? {
        guard let object = try? JSONSerialization.jsonObject(with: stdin) as? [String: Any] else {
            return nil
        }

        // `notify` program payload (delivered via argv, fed in as Data by the CLI).
        // VibePet installs the `Stop` hook instead, but notify is still parsed for
        // robustness if a user wires it up.
        if (object["type"] as? String) == "agent-turn-complete" {
            return makeCompletionEnvelope(
                summary: (object["last-assistant-message"] as? String).flatMap(nonEmpty),
                source: makeSource(from: object, sessionKeys: ["thread-id", "turn-id"])
            )
        }

        guard let event = object["hook_event_name"] as? String else {
            return nil
        }
        switch event {
        case "PermissionRequest":
            return makePermissionEnvelope(from: object)
        case "Stop":
            // Turn-completion: VibePet registers a Codex `Stop` hook (open-vibe-island
            // pattern) and shows the last assistant message as a completion.
            return makeCompletionEnvelope(
                summary: (object["last_assistant_message"] as? String).flatMap(nonEmpty),
                source: makeSource(from: object)
            )
        default:
            // Other lifecycle hooks are outside the MVP subset.
            return nil
        }
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

    private func makePermissionEnvelope(from object: [String: Any]) -> BridgeEnvelope? {
        guard let toolName = (object["tool_name"] as? String).flatMap(nonEmpty) else {
            return nil
        }
        let source = makeSource(from: object)
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
            return makeEnvelope(source: source, content: .approval(content))
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
        return makeEnvelope(source: source, content: .approval(content))
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

    private func makeCompletionEnvelope(summary: String?, source: SourceInfo) -> BridgeEnvelope {
        makeEnvelope(
            source: source,
            content: .completion(CompletionContent(markdownSummary: summary ?? Self.completionFallback, isError: false))
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

    private func makeSource(from object: [String: Any], sessionKeys: [String] = ["session_id"]) -> SourceInfo {
        let cwd = (object["cwd"] as? String).flatMap(nonEmpty)
        let projectName = cwd.map { URL(fileURLWithPath: $0).lastPathComponent }
        let sessionShortId = sessionKeys
            .lazy
            .compactMap { (object[$0] as? String).flatMap(nonEmpty) }
            .first
            .map { String($0.prefix(6)) }

        return SourceInfo(
            tool: .codex,
            projectName: projectName,
            sessionShortId: sessionShortId,
            cwd: cwd
        )
    }

    private func makeEnvelope(source: SourceInfo, content: BubbleContent) -> BridgeEnvelope {
        BridgeEnvelope(requestId: UUID(), source: source, content: content)
    }
}

private func nonEmpty(_ value: String) -> String? {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : value
}
