import Foundation

public protocol ToolAdapter: Sendable {
    var tool: ToolKind { get }

    func parseEvent(stdin: Data, env: [String: String]) throws -> BridgeEnvelope?

    func parseAgentEvent(stdin: Data, env: [String: String]) throws -> AgentEvent?

    func encodeResponse(_ response: BridgeResponse, for envelope: BridgeEnvelope) -> Data
}

public extension ToolAdapter {
    func parseAgentEvent(stdin: Data, env: [String: String]) throws -> AgentEvent? {
        nil
    }
}
