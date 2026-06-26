import Foundation

public enum SessionPhase: String, Codable, Sendable, CaseIterable {
    case running
    case waitingForApproval
    case waitingForAnswer
    case completed

    public var requiresAttention: Bool {
        switch self {
        case .waitingForApproval, .waitingForAnswer:
            true
        case .running, .completed:
            false
        }
    }
}

public enum SessionPetActivity: String, Equatable, Sendable {
    case idle
    case greeting
    case deciding
}

public struct JumpTarget: Codable, Equatable, Sendable {
    public var terminalApp: String
    public var workspaceName: String?
    public var paneTitle: String?
    public var workingDirectory: String?
    public var terminalSessionID: String?
    public var terminalTTY: String?

    public init(
        terminalApp: String,
        workspaceName: String? = nil,
        paneTitle: String? = nil,
        workingDirectory: String? = nil,
        terminalSessionID: String? = nil,
        terminalTTY: String? = nil
    ) {
        self.terminalApp = terminalApp
        self.workspaceName = workspaceName
        self.paneTitle = paneTitle
        self.workingDirectory = workingDirectory
        self.terminalSessionID = terminalSessionID
        self.terminalTTY = terminalTTY
    }
}

public struct AgentSession: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var tool: ToolKind
    public var phase: SessionPhase
    public var summary: String
    public var latestUserPrompt: String?
    public var updatedAt: Date
    public var firstSeenAt: Date
    public var jumpTarget: JumpTarget?
    public var isError: Bool
    public var isSessionEnded: Bool
    public var isProcessAlive: Bool
    public var processNotSeenCount: Int

    public init(
        id: String,
        title: String,
        tool: ToolKind,
        phase: SessionPhase,
        summary: String,
        updatedAt: Date,
        firstSeenAt: Date? = nil,
        jumpTarget: JumpTarget? = nil,
        isError: Bool = false,
        isSessionEnded: Bool = false,
        isProcessAlive: Bool = true,
        processNotSeenCount: Int = 0,
        latestUserPrompt: String? = nil
    ) {
        self.id = id
        self.title = title
        self.tool = tool
        self.phase = phase
        self.summary = summary
        self.latestUserPrompt = latestUserPrompt
        self.updatedAt = updatedAt
        self.firstSeenAt = firstSeenAt ?? updatedAt
        self.jumpTarget = jumpTarget
        self.isError = isError
        self.isSessionEnded = isSessionEnded
        self.isProcessAlive = isProcessAlive
        self.processNotSeenCount = processNotSeenCount
    }

    public var isVisible: Bool {
        if phase.requiresAttention {
            return true
        }
        if !isSessionEnded && isProcessAlive {
            return true
        }
        return false
    }
}
