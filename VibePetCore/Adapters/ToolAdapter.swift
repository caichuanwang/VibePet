import Foundation

public protocol ToolAdapter: Sendable {
    var tool: ToolKind { get }

    func parseEvent(stdin: Data, env: [String: String]) throws -> BridgeEnvelope?

    func encodeResponse(_ response: BridgeResponse, for envelope: BridgeEnvelope) -> Data
}
