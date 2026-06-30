import Foundation
import VibePetCore

struct SessionDashboardProjection: Equatable {
    enum Status: Equatable {
        case idle
        case running
        case attention
        case error
        case completed
    }

    struct Row: Equatable, Identifiable {
        let id: String
        let title: String
        let status: Status
        let toolTag: String
        let terminalTag: String?
        let elapsed: String
        let summary: String
        let latestUserPrompt: String?
        let detailSummary: String?
        let emptyDetailSummary: String
    }

    let rows: [Row]
    let totalCount: Int
    let runningCount: Int
    let attentionCount: Int
    let emptyPetName: String

    init(
        state: SessionState,
        activePetName: String,
        now: Date = .now,
        localizer: AppLocalizer = AppLocalizer(language: .simplifiedChinese)
    ) {
        rows = state.visibleSessions
            .sorted(by: Self.rowPrecedes)
            .map { session in
            Row(
                id: session.id,
                title: session.title,
                status: Self.status(for: session),
                toolTag: Self.toolTag(for: session.tool),
                terminalTag: session.jumpTarget?.terminalApp,
                elapsed: Self.elapsed(from: session.firstSeenAt, to: now),
                summary: session.summary,
                latestUserPrompt: session.latestUserPrompt,
                detailSummary: Self.detailSummary(for: session),
                emptyDetailSummary: Self.emptyDetailSummary(for: session, localizer: localizer)
            )
        }
        totalCount = state.visibleSessions.count
        runningCount = state.runningCount
        attentionCount = state.attentionCount
        emptyPetName = activePetName
    }

    var isEmpty: Bool {
        rows.isEmpty
    }

    func resolvedSelection(current: String?) -> String? {
        if let current, rows.contains(where: { $0.id == current }) {
            return current
        }
        return rows.first?.id
    }

    private static func rowPrecedes(_ lhs: AgentSession, _ rhs: AgentSession) -> Bool {
        let lhsRank = statusRank(status(for: lhs))
        let rhsRank = statusRank(status(for: rhs))
        if lhsRank != rhsRank {
            return lhsRank < rhsRank
        }
        if lhs.updatedAt == rhs.updatedAt {
            return lhs.id < rhs.id
        }
        return lhs.updatedAt > rhs.updatedAt
    }

    private static func statusRank(_ status: Status) -> Int {
        switch status {
        case .attention:
            0
        case .running:
            1
        case .error:
            2
        case .idle:
            3
        case .completed:
            4
        }
    }

    static func status(for session: AgentSession) -> Status {
        if session.phase.requiresAttention {
            return .attention
        }
        if session.phase == .completed, session.isError {
            return .error
        }
        if session.phase == .completed, session.jumpTarget != nil, session.isProcessAlive {
            return .idle
        }
        if session.phase == .completed {
            return .completed
        }
        return .running
    }

    static func toolTag(for tool: ToolKind) -> String {
        switch tool {
        case .claudeCode:
            "claude"
        case .codex:
            "codex"
        }
    }

    static func detailSummary(for session: AgentSession) -> String? {
        let summary = session.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !summary.isEmpty else { return nil }
        if SessionState.isUserPromptSummary(summary) {
            return nil
        }
        if session.id.hasPrefix("discovered-"), summary.hasPrefix("Detected running ") {
            return nil
        }
        return summary
    }

    static func emptyDetailSummary(
        for session: AgentSession,
        localizer: AppLocalizer = AppLocalizer(language: .simplifiedChinese)
    ) -> String {
        switch session.phase {
        case .running:
            return localizer.text(.sessionWaitingForOutput)
        case .waitingForApproval:
            return localizer.text(.sessionWaitingForApproval)
        case .waitingForAnswer:
            return localizer.text(.sessionWaitingForAnswer)
        case .completed:
            return session.isError ? localizer.text(.sessionEndedWithError) : localizer.text(.sessionCompleted)
        }
    }

    static func elapsed(from start: Date, to now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(start)))
        if seconds < 60 {
            return "\(seconds)s"
        }
        let minutes = seconds / 60
        if minutes < 60 {
            return "\(minutes)m"
        }
        let hours = minutes / 60
        return "\(hours)h"
    }
}
