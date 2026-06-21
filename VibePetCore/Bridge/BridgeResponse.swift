import Foundation

public struct BridgeResponseEnvelope: Codable, Equatable, Sendable {
    public let requestId: UUID
    public let response: BridgeResponse

    public init(requestId: UUID, response: BridgeResponse) {
        self.requestId = requestId
        self.response = response
    }
}

public enum BridgeResponse: Codable, Equatable, Sendable {
    case approval(ApprovalDecision)
    case question(QuestionAnswer)
    case `defer`

    private enum CodingKeys: String, CodingKey {
        case type
        case approval
        case question
    }

    private enum ResponseType: String, Codable {
        case approval
        case question
        case `defer`
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(ResponseType.self, forKey: .type)

        switch type {
        case .approval:
            self = .approval(try container.decode(ApprovalDecision.self, forKey: .approval))
        case .question:
            self = .question(try container.decode(QuestionAnswer.self, forKey: .question))
        case .defer:
            self = .defer
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case let .approval(decision):
            try container.encode(ResponseType.approval, forKey: .type)
            try container.encode(decision, forKey: .approval)
        case let .question(answer):
            try container.encode(ResponseType.question, forKey: .type)
            try container.encode(answer, forKey: .question)
        case .defer:
            try container.encode(ResponseType.defer, forKey: .type)
        }
    }
}

public enum ApprovalDecision: Codable, Equatable, Sendable {
    case allowOnce
    case allowAlways(scopeHint: String)
    case deny(reason: String?)

    private enum CodingKeys: String, CodingKey {
        case type
        case scopeHint
        case reason
    }

    private enum DecisionType: String, Codable {
        case allowOnce
        case allowAlways
        case deny
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(DecisionType.self, forKey: .type)

        switch type {
        case .allowOnce:
            self = .allowOnce
        case .allowAlways:
            self = .allowAlways(scopeHint: try container.decode(String.self, forKey: .scopeHint))
        case .deny:
            self = .deny(reason: try container.decodeIfPresent(String.self, forKey: .reason))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .allowOnce:
            try container.encode(DecisionType.allowOnce, forKey: .type)
        case let .allowAlways(scopeHint):
            try container.encode(DecisionType.allowAlways, forKey: .type)
            try container.encode(scopeHint, forKey: .scopeHint)
        case let .deny(reason):
            try container.encode(DecisionType.deny, forKey: .type)
            try container.encodeIfPresent(reason, forKey: .reason)
        }
    }
}

public struct QuestionAnswer: Codable, Equatable, Sendable {
    /// One value per answered question, keyed by `QuestionItem.header`. Single-select
    /// is the chosen label; multi-select is the chosen labels joined with `", "`; a
    /// freeform ("其他") choice contributes the user's typed text in place of its
    /// label (matching how Claude Code's CLI inlines free text into the answer value
    /// — there is no separate freeform/annotations channel).
    public let answers: [String: String]

    public init(answers: [String: String]) {
        self.answers = answers
    }
}
