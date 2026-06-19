import Foundation

/// Classifies an approval action into a `RiskLevel` from the tool name plus its
/// command/argument text (technical design §8.1). The dangerous-pattern rule set
/// is data-driven so individual rules are unit-testable and the policy can be
/// tuned without touching the matching logic. Lives in `VibePetCore` — pure, no
/// UI, no network — so the adapter can tag `ApprovalContent.risk` at parse time.
public struct RiskClassifier: Sendable {
    /// A dangerous command pattern. `regex` is matched case-insensitively against
    /// the command text; a match escalates the action to `.high`.
    public struct DangerPattern: Sendable {
        public let name: String
        public let regex: String

        public init(name: String, regex: String) {
            self.name = name
            self.regex = regex
        }
    }

    private let dangerPatterns: [DangerPattern]

    /// Default high-risk patterns (§8.1): recursive force-remove, privilege
    /// escalation, piping a network download into a shell, and force-push.
    public static let defaultDangerPatterns: [DangerPattern] = [
        // rm with both -r and -f in any flag order: `rm -rf`, `rm -fr`, `rm -r -f`.
        DangerPattern(name: "recursive-force-remove", regex: #"(?:^|[\s;&|])rm\s+(?:-\S*\s+)*-?\S*(?:rf|fr)\S*"#),
        DangerPattern(name: "recursive-force-remove-split", regex: #"(?:^|[\s;&|])rm\s+(?=(?:\S*\s+)*-\S*r)(?=(?:\S*\s+)*-\S*f)"#),
        DangerPattern(name: "privilege-escalation", regex: #"(?:^|[\s;&|])sudo(?:\s|$)"#),
        DangerPattern(name: "pipe-download-to-shell", regex: #"(?:curl|wget)\b[^|]*\|\s*(?:sudo\s+)?(?:sh|bash|zsh)\b"#),
        DangerPattern(name: "force-push", regex: #"git\s+push\b[^\n]*(?:--force\b|--force-with-lease\b|\s-f\b)"#),
    ]

    public init(dangerPatterns: [DangerPattern] = RiskClassifier.defaultDangerPatterns) {
        self.dangerPatterns = dangerPatterns
    }

    /// Maps a tool name plus optional command text to a `RiskLevel`.
    ///
    /// - A `command` matching any dangerous pattern is `.high`, regardless of tool.
    /// - Otherwise read-only `Read` is `.low`; everything else that mutates state
    ///   or reaches the network defaults to `.medium`.
    public func classify(toolName: String, command: String?) -> RiskLevel {
        if let command, matchesDanger(command) {
            return .high
        }

        switch toolName {
        case "Read":
            return .low
        default:
            return .medium
        }
    }

    private func matchesDanger(_ command: String) -> Bool {
        let range = NSRange(command.startIndex..<command.endIndex, in: command)
        for pattern in dangerPatterns {
            guard
                let regex = try? NSRegularExpression(pattern: pattern.regex, options: [.caseInsensitive])
            else {
                continue
            }
            if regex.firstMatch(in: command, options: [], range: range) != nil {
                return true
            }
        }
        return false
    }
}
