import Foundation

public enum HookDecisionBudget {
    public static func nativeHookTimeout(for tool: ToolKind) -> TimeInterval {
        switch tool {
        case .claudeCode: 86_400
        case .codex: 3_600
        }
    }

    public static func cliReadTimeout(for tool: ToolKind) -> TimeInterval {
        switch tool {
        case .claudeCode: 86_390
        case .codex: 3_590
        }
    }

    public static func appDecisionTimeout(for tool: ToolKind) -> TimeInterval {
        switch tool {
        case .claudeCode: 86_385
        case .codex: 3_585
        }
    }
}

/// Selects how the `VibePetHooks` CLI is invoked: which `ToolAdapter` to use and
/// where the event JSON comes from. Codex registers two surfaces pointing at the
/// same binary — `PermissionRequest` hooks (JSON on stdin) and the `notify` program
/// (`agent-turn-complete` JSON passed as the last argv) — both tagged with
/// `--tool codex`; `notify` additionally carries `--notify`. Claude Code uses the
/// default (no `--tool`), JSON on stdin.
///
/// Pure and table-driven so the routing is unit-testable; `main.swift` is a thin
/// shell over it (technical design §4.2 / §1.2).
public enum HookInvocation {
    /// The adapter for an explicit `--tool` value. Unknown/absent → Claude Code.
    public static func adapter(forTool toolArgument: String?) -> any ToolAdapter {
        switch toolArgument {
        case "codex":
            return CodexAdapter()
        default:
            return ClaudeCodeAdapter()
        }
    }

    /// The value following `--tool` in the argument list, or nil if absent.
    public static func toolArgument(in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: "--tool"), index + 1 < arguments.count else {
            return nil
        }
        return arguments[index + 1]
    }

    /// Whether this is a Codex `notify` invocation (payload in argv, not stdin).
    public static func isNotify(arguments: [String]) -> Bool {
        arguments.contains("--notify")
    }

    /// The event bytes to parse: the last argv for a `notify` invocation (Codex
    /// appends the JSON payload there), otherwise stdin.
    public static func eventData(arguments: [String], stdin: Data) -> Data {
        guard isNotify(arguments: arguments), let last = arguments.last, last != "--notify" else {
            return stdin
        }
        return Data(last.utf8)
    }
}
