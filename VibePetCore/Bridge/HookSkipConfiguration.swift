import Foundation

/// Per-process opt-out for VibePet hooks. When another local controller intentionally
/// owns a child agent's permission flow, it can set `VIBEPET_SKIP_HOOKS=1` on that
/// process so the `VibePetHooks` CLI exits immediately — without reading stdin or
/// touching the bridge — instead of brokering the event. This is a single-process
/// switch: it never changes the global install state, so other agents are unaffected.
///
/// Pure and table-driven so `main.swift` stays a thin shell (cf. `HookInvocation`).
public enum HookSkipConfiguration {
    /// Environment key that disables VibePet hooks for the current process.
    public static let skipKey = "VIBEPET_SKIP_HOOKS"

    /// Whether the given environment asks this process to no-op its hook.
    public static func shouldSkip(environment: [String: String]) -> Bool {
        isTruthy(environment[skipKey])
    }

    /// Interprets common shell-friendly truthy values; everything else is false.
    public static func isTruthy(_ value: String?) -> Bool {
        guard let value else { return false }
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "1", "true", "yes", "on":
            return true
        default:
            return false
        }
    }
}
