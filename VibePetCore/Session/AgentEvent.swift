import Foundation

public enum AgentEvent: Equatable, Sendable {
    case sessionStarted(
        sessionID: String,
        timestamp: Date,
        title: String,
        tool: ToolKind,
        summary: String,
        jumpTarget: JumpTarget?
    )
    case activityUpdated(
        sessionID: String,
        timestamp: Date,
        summary: String
    )
    case permissionRequested(
        sessionID: String,
        timestamp: Date,
        summary: String
    )
    case questionAsked(
        sessionID: String,
        timestamp: Date,
        summary: String
    )
    case sessionCompleted(
        sessionID: String,
        timestamp: Date,
        summary: String,
        isError: Bool,
        isSessionEnd: Bool
    )
    case jumpTargetUpdated(
        sessionID: String,
        timestamp: Date,
        jumpTarget: JumpTarget
    )
    case actionableStateResolved(
        sessionID: String,
        timestamp: Date,
        summary: String
    )

    public var sessionID: String {
        switch self {
        case let .sessionStarted(sessionID, _, _, _, _, _),
             let .activityUpdated(sessionID, _, _),
             let .permissionRequested(sessionID, _, _),
             let .questionAsked(sessionID, _, _),
             let .sessionCompleted(sessionID, _, _, _, _),
             let .jumpTargetUpdated(sessionID, _, _),
             let .actionableStateResolved(sessionID, _, _):
            sessionID
        }
    }

    public var timestamp: Date {
        switch self {
        case let .sessionStarted(_, timestamp, _, _, _, _),
             let .activityUpdated(_, timestamp, _),
             let .permissionRequested(_, timestamp, _),
             let .questionAsked(_, timestamp, _),
             let .sessionCompleted(_, timestamp, _, _, _),
             let .jumpTargetUpdated(_, timestamp, _),
             let .actionableStateResolved(_, timestamp, _):
            timestamp
        }
    }

    public var isSessionStart: Bool {
        if case .sessionStarted = self { return true }
        return false
    }

    public func rekeyed(to newSessionID: String) -> AgentEvent {
        switch self {
        case let .sessionStarted(_, timestamp, title, tool, summary, jumpTarget):
            return .sessionStarted(
                sessionID: newSessionID,
                timestamp: timestamp,
                title: title,
                tool: tool,
                summary: summary,
                jumpTarget: jumpTarget
            )
        case let .activityUpdated(_, timestamp, summary):
            return .activityUpdated(sessionID: newSessionID, timestamp: timestamp, summary: summary)
        case let .permissionRequested(_, timestamp, summary):
            return .permissionRequested(sessionID: newSessionID, timestamp: timestamp, summary: summary)
        case let .questionAsked(_, timestamp, summary):
            return .questionAsked(sessionID: newSessionID, timestamp: timestamp, summary: summary)
        case let .sessionCompleted(_, timestamp, summary, isError, isSessionEnd):
            return .sessionCompleted(
                sessionID: newSessionID,
                timestamp: timestamp,
                summary: summary,
                isError: isError,
                isSessionEnd: isSessionEnd
            )
        case let .jumpTargetUpdated(_, timestamp, jumpTarget):
            return .jumpTargetUpdated(sessionID: newSessionID, timestamp: timestamp, jumpTarget: jumpTarget)
        case let .actionableStateResolved(_, timestamp, summary):
            return .actionableStateResolved(sessionID: newSessionID, timestamp: timestamp, summary: summary)
        }
    }
}

extension AgentEvent: Codable {
    private enum CodingKeys: String, CodingKey {
        case type
        case sessionID
        case timestamp
        case title
        case tool
        case summary
        case jumpTarget
        case isError
        case isSessionEnd
    }

    private enum EventType: String, Codable {
        case sessionStarted
        case activityUpdated
        case permissionRequested
        case questionAsked
        case sessionCompleted
        case jumpTargetUpdated
        case actionableStateResolved
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(EventType.self, forKey: .type)
        let sessionID = try container.decode(String.self, forKey: .sessionID)
        let timestamp = try container.decode(Date.self, forKey: .timestamp)

        switch type {
        case .sessionStarted:
            self = .sessionStarted(
                sessionID: sessionID,
                timestamp: timestamp,
                title: try container.decode(String.self, forKey: .title),
                tool: try container.decode(ToolKind.self, forKey: .tool),
                summary: try container.decode(String.self, forKey: .summary),
                jumpTarget: try container.decodeIfPresent(JumpTarget.self, forKey: .jumpTarget)
            )
        case .activityUpdated:
            self = .activityUpdated(
                sessionID: sessionID,
                timestamp: timestamp,
                summary: try container.decode(String.self, forKey: .summary)
            )
        case .permissionRequested:
            self = .permissionRequested(
                sessionID: sessionID,
                timestamp: timestamp,
                summary: try container.decode(String.self, forKey: .summary)
            )
        case .questionAsked:
            self = .questionAsked(
                sessionID: sessionID,
                timestamp: timestamp,
                summary: try container.decode(String.self, forKey: .summary)
            )
        case .sessionCompleted:
            self = .sessionCompleted(
                sessionID: sessionID,
                timestamp: timestamp,
                summary: try container.decode(String.self, forKey: .summary),
                isError: try container.decode(Bool.self, forKey: .isError),
                isSessionEnd: try container.decode(Bool.self, forKey: .isSessionEnd)
            )
        case .jumpTargetUpdated:
            self = .jumpTargetUpdated(
                sessionID: sessionID,
                timestamp: timestamp,
                jumpTarget: try container.decode(JumpTarget.self, forKey: .jumpTarget)
            )
        case .actionableStateResolved:
            self = .actionableStateResolved(
                sessionID: sessionID,
                timestamp: timestamp,
                summary: try container.decode(String.self, forKey: .summary)
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case let .sessionStarted(sessionID, timestamp, title, tool, summary, jumpTarget):
            try container.encode(EventType.sessionStarted, forKey: .type)
            try container.encode(sessionID, forKey: .sessionID)
            try container.encode(timestamp, forKey: .timestamp)
            try container.encode(title, forKey: .title)
            try container.encode(tool, forKey: .tool)
            try container.encode(summary, forKey: .summary)
            try container.encodeIfPresent(jumpTarget, forKey: .jumpTarget)
        case let .activityUpdated(sessionID, timestamp, summary):
            try container.encode(EventType.activityUpdated, forKey: .type)
            try container.encode(sessionID, forKey: .sessionID)
            try container.encode(timestamp, forKey: .timestamp)
            try container.encode(summary, forKey: .summary)
        case let .permissionRequested(sessionID, timestamp, summary):
            try container.encode(EventType.permissionRequested, forKey: .type)
            try container.encode(sessionID, forKey: .sessionID)
            try container.encode(timestamp, forKey: .timestamp)
            try container.encode(summary, forKey: .summary)
        case let .questionAsked(sessionID, timestamp, summary):
            try container.encode(EventType.questionAsked, forKey: .type)
            try container.encode(sessionID, forKey: .sessionID)
            try container.encode(timestamp, forKey: .timestamp)
            try container.encode(summary, forKey: .summary)
        case let .sessionCompleted(sessionID, timestamp, summary, isError, isSessionEnd):
            try container.encode(EventType.sessionCompleted, forKey: .type)
            try container.encode(sessionID, forKey: .sessionID)
            try container.encode(timestamp, forKey: .timestamp)
            try container.encode(summary, forKey: .summary)
            try container.encode(isError, forKey: .isError)
            try container.encode(isSessionEnd, forKey: .isSessionEnd)
        case let .jumpTargetUpdated(sessionID, timestamp, jumpTarget):
            try container.encode(EventType.jumpTargetUpdated, forKey: .type)
            try container.encode(sessionID, forKey: .sessionID)
            try container.encode(timestamp, forKey: .timestamp)
            try container.encode(jumpTarget, forKey: .jumpTarget)
        case let .actionableStateResolved(sessionID, timestamp, summary):
            try container.encode(EventType.actionableStateResolved, forKey: .type)
            try container.encode(sessionID, forKey: .sessionID)
            try container.encode(timestamp, forKey: .timestamp)
            try container.encode(summary, forKey: .summary)
        }
    }
}
