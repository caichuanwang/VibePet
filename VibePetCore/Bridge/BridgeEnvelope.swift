import Foundation

public struct BridgeEnvelope: Codable, Equatable, Sendable {
    public let version: Int
    public let requestId: UUID
    public let source: SourceInfo
    public let content: BubbleContent
    public let agentEvent: AgentEvent?

    public init(
        version: Int = VibePetCore.protocolVersion,
        requestId: UUID,
        source: SourceInfo,
        content: BubbleContent,
        agentEvent: AgentEvent? = nil
    ) {
        self.version = version
        self.requestId = requestId
        self.source = source
        self.content = content
        self.agentEvent = agentEvent
    }
}

public struct SourceInfo: Codable, Equatable, Sendable {
    public let tool: ToolKind
    public let projectName: String?
    public let sessionID: String
    public let sessionShortId: String?
    public let cwd: String?
    public let jumpTarget: JumpTarget?

    public init(
        tool: ToolKind,
        projectName: String?,
        sessionID: String? = nil,
        sessionShortId: String?,
        cwd: String?,
        jumpTarget: JumpTarget? = nil
    ) {
        self.tool = tool
        self.projectName = projectName
        self.sessionID = Self.stableFallbackSessionID(tool: tool, sessionID: sessionID, sessionShortId: sessionShortId)
        self.sessionShortId = sessionShortId
        self.cwd = cwd
        self.jumpTarget = jumpTarget
    }

    private enum CodingKeys: String, CodingKey {
        case tool
        case projectName
        case sessionID
        case sessionShortId
        case cwd
        case jumpTarget
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tool = try container.decode(ToolKind.self, forKey: .tool)
        projectName = try container.decodeIfPresent(String.self, forKey: .projectName)
        sessionShortId = try container.decodeIfPresent(String.self, forKey: .sessionShortId)
        cwd = try container.decodeIfPresent(String.self, forKey: .cwd)
        jumpTarget = try container.decodeIfPresent(JumpTarget.self, forKey: .jumpTarget)
        let decodedSessionID = try container.decodeIfPresent(String.self, forKey: .sessionID)
        sessionID = Self.stableFallbackSessionID(tool: tool, sessionID: decodedSessionID, sessionShortId: sessionShortId)
    }

    private static func stableFallbackSessionID(tool: ToolKind, sessionID: String?, sessionShortId: String?) -> String {
        sessionID ?? sessionShortId ?? "unknown-\(tool.rawValue)"
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(tool, forKey: .tool)
        try container.encodeIfPresent(projectName, forKey: .projectName)
        try container.encode(sessionID, forKey: .sessionID)
        try container.encodeIfPresent(sessionShortId, forKey: .sessionShortId)
        try container.encodeIfPresent(cwd, forKey: .cwd)
        try container.encodeIfPresent(jumpTarget, forKey: .jumpTarget)
    }
}

public enum ToolKind: String, Codable, Equatable, Sendable {
    case claudeCode
    case codex
}

public enum BubbleContent: Codable, Equatable, Sendable {
    case approval(ApprovalContent)
    case question(QuestionContent)
    case completion(CompletionContent)
    case status(StatusContent)

    public var needsResponse: Bool {
        switch self {
        case .approval, .question:
            true
        case .completion, .status:
            false
        }
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case approval
        case question
        case completion
        case status
    }

    private enum ContentType: String, Codable {
        case approval
        case question
        case completion
        case status
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(ContentType.self, forKey: .type)

        switch type {
        case .approval:
            self = .approval(try container.decode(ApprovalContent.self, forKey: .approval))
        case .question:
            self = .question(try container.decode(QuestionContent.self, forKey: .question))
        case .completion:
            self = .completion(try container.decode(CompletionContent.self, forKey: .completion))
        case .status:
            self = .status(try container.decode(StatusContent.self, forKey: .status))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case let .approval(content):
            try container.encode(ContentType.approval, forKey: .type)
            try container.encode(content, forKey: .approval)
        case let .question(content):
            try container.encode(ContentType.question, forKey: .type)
            try container.encode(content, forKey: .question)
        case let .completion(content):
            try container.encode(ContentType.completion, forKey: .type)
            try container.encode(content, forKey: .completion)
        case let .status(content):
            try container.encode(ContentType.status, forKey: .type)
            try container.encode(content, forKey: .status)
        }
    }
}

public struct ApprovalContent: Codable, Equatable, Sendable {
    public let title: String
    public let risk: RiskLevel
    public let preview: ActionPreview
    public let allowLabel: String
    public let denyLabel: String
    public let alwaysAllow: AlwaysAllowOption?
    public let requiresTerminalApproval: Bool

    public init(
        title: String,
        risk: RiskLevel,
        preview: ActionPreview,
        allowLabel: String = "允许一次",
        denyLabel: String = "拒绝",
        alwaysAllow: AlwaysAllowOption?,
        requiresTerminalApproval: Bool
    ) {
        self.title = title
        self.risk = risk
        self.preview = preview
        self.allowLabel = allowLabel
        self.denyLabel = denyLabel
        self.alwaysAllow = alwaysAllow
        self.requiresTerminalApproval = requiresTerminalApproval
    }
}

public struct AlwaysAllowOption: Codable, Equatable, Sendable {
    public let label: String
    public let scopeHint: String

    public init(label: String, scopeHint: String) {
        self.label = label
        self.scopeHint = scopeHint
    }
}

public enum RiskLevel: String, Codable, Equatable, Sendable {
    case low
    case medium
    case high
}

public enum ActionPreview: Codable, Equatable, Sendable {
    case command(text: String)
    case fileChange(path: String, added: Int, removed: Int)
    case fileRead(path: String)
    case network(target: String)
    case generic(summary: String)

    private enum CodingKeys: String, CodingKey {
        case type
        case text
        case path
        case added
        case removed
        case target
        case summary
    }

    private enum PreviewType: String, Codable {
        case command
        case fileChange
        case fileRead
        case network
        case generic
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(PreviewType.self, forKey: .type)

        switch type {
        case .command:
            self = .command(text: try container.decode(String.self, forKey: .text))
        case .fileChange:
            self = .fileChange(
                path: try container.decode(String.self, forKey: .path),
                added: try container.decode(Int.self, forKey: .added),
                removed: try container.decode(Int.self, forKey: .removed)
            )
        case .fileRead:
            self = .fileRead(path: try container.decode(String.self, forKey: .path))
        case .network:
            self = .network(target: try container.decode(String.self, forKey: .target))
        case .generic:
            self = .generic(summary: try container.decode(String.self, forKey: .summary))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case let .command(text):
            try container.encode(PreviewType.command, forKey: .type)
            try container.encode(text, forKey: .text)
        case let .fileChange(path, added, removed):
            try container.encode(PreviewType.fileChange, forKey: .type)
            try container.encode(path, forKey: .path)
            try container.encode(added, forKey: .added)
            try container.encode(removed, forKey: .removed)
        case let .fileRead(path):
            try container.encode(PreviewType.fileRead, forKey: .type)
            try container.encode(path, forKey: .path)
        case let .network(target):
            try container.encode(PreviewType.network, forKey: .type)
            try container.encode(target, forKey: .target)
        case let .generic(summary):
            try container.encode(PreviewType.generic, forKey: .type)
            try container.encode(summary, forKey: .summary)
        }
    }
}

public struct QuestionContent: Codable, Equatable, Sendable {
    public let title: String
    public let questions: [QuestionItem]

    public init(title: String, questions: [QuestionItem]) {
        self.title = title
        self.questions = questions
    }
}

public struct QuestionItem: Codable, Equatable, Sendable {
    public let header: String
    public let prompt: String
    public let options: [QuestionOption]
    public let multiSelect: Bool

    public init(
        header: String,
        prompt: String,
        options: [QuestionOption],
        multiSelect: Bool
    ) {
        self.header = header
        self.prompt = prompt
        self.options = options
        self.multiSelect = multiSelect
    }
}

public struct QuestionOption: Codable, Equatable, Sendable {
    public let label: String
    public let detail: String?
    public let allowsFreeform: Bool

    public init(label: String, detail: String?, allowsFreeform: Bool) {
        self.label = label
        self.detail = detail
        self.allowsFreeform = allowsFreeform
    }
}

public struct CompletionContent: Codable, Equatable, Sendable {
    public let markdownSummary: String
    public let isError: Bool

    public init(markdownSummary: String, isError: Bool) {
        self.markdownSummary = markdownSummary
        self.isError = isError
    }
}

public struct StatusContent: Codable, Equatable, Sendable {
    public let text: String

    public init(text: String) {
        self.text = text
    }
}
