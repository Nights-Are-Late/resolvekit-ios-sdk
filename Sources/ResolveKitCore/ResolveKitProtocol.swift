import Foundation

public struct ResolveKitEnvelope: Codable, Sendable, Equatable {
    public let type: String
    public let turnID: String?
    public let requestID: String?
    public let payload: JSONObject
    public let timestamp: String?

    public init(type: String, turnID: String? = nil, requestID: String? = nil, payload: JSONObject, timestamp: String? = nil) {
        self.type = type
        self.turnID = turnID
        self.requestID = requestID
        self.payload = payload
        self.timestamp = timestamp
    }

    enum CodingKeys: String, CodingKey {
        case type
        case turnID = "turn_id"
        case requestID = "request_id"
        case payload
        case timestamp
    }
}

public struct ResolveKitSession: Codable, Sendable, Equatable {
    public let id: String
    public let eventsURL: String
    public let chatCapabilityToken: String
    public let reusedActiveSession: Bool
    public let availableFunctionNames: [String]
    public let locale: String
    public let chatTitle: String
    public let messagePlaceholder: String
    public let initialMessage: String

    public init(
        id: String,
        eventsURL: String,
        chatCapabilityToken: String,
        reusedActiveSession: Bool = false,
        availableFunctionNames: [String] = [],
        locale: String = "en",
        chatTitle: String = "Support Chat",
        messagePlaceholder: String = "Message",
        initialMessage: String = "Hello! How can I help you today?"
    ) {
        self.id = id
        self.eventsURL = eventsURL
        self.chatCapabilityToken = chatCapabilityToken
        self.reusedActiveSession = reusedActiveSession
        self.availableFunctionNames = availableFunctionNames
        self.locale = locale
        self.chatTitle = chatTitle
        self.messagePlaceholder = messagePlaceholder
        self.initialMessage = initialMessage
    }

    enum CodingKeys: String, CodingKey {
        case id
        case eventsURL = "events_url"
        case chatCapabilityToken = "chat_capability_token"
        case reusedActiveSession = "reused_active_session"
        case availableFunctionNames = "available_function_names"
        case locale
        case chatTitle = "chat_title"
        case messagePlaceholder = "message_placeholder"
        case initialMessage = "initial_message"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        eventsURL = try c.decode(String.self, forKey: .eventsURL)
        chatCapabilityToken = try c.decode(String.self, forKey: .chatCapabilityToken)
        reusedActiveSession = try c.decodeIfPresent(Bool.self, forKey: .reusedActiveSession) ?? false
        availableFunctionNames = try c.decodeIfPresent([String].self, forKey: .availableFunctionNames) ?? []
        locale = try c.decodeIfPresent(String.self, forKey: .locale) ?? "en"
        chatTitle = try c.decodeIfPresent(String.self, forKey: .chatTitle) ?? "Support Chat"
        messagePlaceholder = try c.decodeIfPresent(String.self, forKey: .messagePlaceholder) ?? "Message"
        initialMessage = try c.decodeIfPresent(String.self, forKey: .initialMessage) ?? "Hello! How can I help you today?"
    }
}

public struct ResolveKitToolCallRequest: Codable, Sendable, Equatable {
    public let callID: String
    public let functionName: String
    public let arguments: JSONObject
    public let timeoutSeconds: Int
    public let humanDescription: String
    public let requiresApproval: Bool

    public init(callID: String, functionName: String, arguments: JSONObject, timeoutSeconds: Int, humanDescription: String = "", requiresApproval: Bool = true) {
        self.callID = callID
        self.functionName = functionName
        self.arguments = arguments
        self.timeoutSeconds = timeoutSeconds
        self.humanDescription = humanDescription
        self.requiresApproval = requiresApproval
    }

    enum CodingKeys: String, CodingKey {
        case callID = "call_id"
        case functionName = "function_name"
        case arguments
        case timeoutSeconds = "timeout_seconds"
        case humanDescription = "human_description"
        case requiresApproval = "requires_approval"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        callID = try c.decode(String.self, forKey: .callID)
        functionName = try c.decode(String.self, forKey: .functionName)
        arguments = try c.decode(JSONObject.self, forKey: .arguments)
        timeoutSeconds = try c.decode(Int.self, forKey: .timeoutSeconds)
        humanDescription = (try? c.decode(String.self, forKey: .humanDescription)) ?? ""
        requiresApproval = (try? c.decode(Bool.self, forKey: .requiresApproval)) ?? true
    }
}

public struct ResolveKitTurnComplete: Codable, Sendable, Equatable {
    public let fullText: String

    enum CodingKeys: String, CodingKey {
        case fullText = "full_text"
    }
}

public struct ResolveKitTextDelta: Codable, Sendable, Equatable {
    public let delta: String
    public let accumulated: String
}

public struct ResolveKitServerErrorPayload: Codable, Sendable, Equatable {
    public let code: String
    public let message: String
    public let recoverable: Bool
}

public enum ResolveKitToolResultStatus: String, Codable, Sendable {
    case success
    case error
}

public struct ResolveKitToolResultPayload: Codable, Sendable, Equatable {
    public let callID: String
    public let status: ResolveKitToolResultStatus
    public let result: JSONValue?
    public let error: String?

    public init(callID: String, status: ResolveKitToolResultStatus, result: JSONValue? = nil, error: String? = nil) {
        self.callID = callID
        self.status = status
        self.result = result
        self.error = error
    }

    enum CodingKeys: String, CodingKey {
        case callID = "call_id"
        case status
        case result
        case error
    }
}

public enum ResolveKitConnectionState: String, Sendable {
    case idle
    case registering
    case connecting
    case active
    case reconnected
    case reconnecting
    case blocked
    case failed
}

public struct ResolveKitChatMessage: Identifiable, Equatable, Sendable {
    public enum Role: String, Sendable {
        case user
        case assistant
        case system
    }

    public let id: UUID
    public let role: Role
    public let text: String
    public let createdAt: Date

    public init(id: UUID = UUID(), role: Role, text: String, createdAt: Date = Date()) {
        self.id = id
        self.role = role
        self.text = text
        self.createdAt = createdAt
    }
}

public struct ResolveKitPendingToolCall: Identifiable, Equatable, Sendable {
    public let id: String
    public let functionName: String
    public let arguments: JSONObject
    public let timeoutSeconds: Int
    public let humanDescription: String
    public let createdAt: Date

    public init(id: String, functionName: String, arguments: JSONObject, timeoutSeconds: Int, humanDescription: String = "", createdAt: Date = Date()) {
        self.id = id
        self.functionName = functionName
        self.arguments = arguments
        self.timeoutSeconds = timeoutSeconds
        self.humanDescription = humanDescription
        self.createdAt = createdAt
    }
}
