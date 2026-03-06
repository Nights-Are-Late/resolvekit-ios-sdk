import Foundation
import ResolveKitCore

private enum ResolveKitNetworkLogger {
    static func log(_ message: String) {
        print("[ResolveKit][HTTP] \(message)")
    }
}

public enum ResolveKitAPIClientError: Error, LocalizedError {
    case missingAPIKey
    case invalidResponse
    case chatUnavailable
    case serverError(statusCode: Int, message: String)
    case methodNotAllowed(method: String, path: String, payload: String, response: String)

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Missing API key"
        case .invalidResponse:
            return "Invalid server response"
        case .chatUnavailable:
            return "Chat is unavailable, try again later"
        case .serverError(let statusCode, let message):
            return "Server error (\(statusCode)): \(message)"
        case .methodNotAllowed(let method, let path, let payload, let response):
            return "405 Method Not Allowed for \(method) \(path). Payload: \(payload). Response: \(response)"
        }
    }
}

public struct ResolveKitSessionCreateRequest: Codable, Sendable {
    public let deviceID: String?
    public let client: [String: String]?
    public let llmContext: JSONObject
    public let availableFunctionNames: [String]
    public let locale: String?
    public let preferredLocales: [String]
    public let reuseActiveSession: Bool

    public init(
        deviceID: String?,
        client: [String: String]? = nil,
        llmContext: JSONObject = [:],
        availableFunctionNames: [String],
        locale: String? = nil,
        preferredLocales: [String] = [],
        reuseActiveSession: Bool = true
    ) {
        self.deviceID = deviceID
        self.client = client
        self.llmContext = llmContext
        self.availableFunctionNames = availableFunctionNames
        self.locale = locale
        self.preferredLocales = preferredLocales
        self.reuseActiveSession = reuseActiveSession
    }

    enum CodingKeys: String, CodingKey {
        case deviceID = "device_id"
        case client
        case llmContext = "llm_context"
        case availableFunctionNames = "available_function_names"
        case locale
        case preferredLocales = "preferred_locales"
        case reuseActiveSession = "reuse_active_session"
    }
}

public struct ResolveKitSessionContextPatchRequest: Codable, Sendable {
    public let client: [String: String]?
    public let llmContext: JSONObject?
    public let availableFunctionNames: [String]
    public let locale: String?

    public init(
        client: [String: String]? = nil,
        llmContext: JSONObject? = nil,
        availableFunctionNames: [String],
        locale: String? = nil
    ) {
        self.client = client
        self.llmContext = llmContext
        self.availableFunctionNames = availableFunctionNames
        self.locale = locale
    }

    enum CodingKeys: String, CodingKey {
        case client
        case llmContext = "llm_context"
        case availableFunctionNames = "available_function_names"
        case locale
    }
}

public struct ResolveKitSessionContextOut: Codable, Sendable, Equatable {
    public let id: String
    public let appID: String
    public let clientContext: JSONObject?
    public let llmContext: JSONObject?
    public let availableFunctionNames: [String]
    public let locale: String
    public let lastActivityAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case appID = "app_id"
        case clientContext = "client_context"
        case llmContext = "llm_context"
        case availableFunctionNames = "available_function_names"
        case locale
        case lastActivityAt = "last_activity_at"
    }
}

public struct ResolveKitSessionLocalization: Codable, Sendable, Equatable {
    public let locale: String
    public let chatTitle: String
    public let messagePlaceholder: String
    public let initialMessage: String

    enum CodingKeys: String, CodingKey {
        case locale
        case chatTitle = "chat_title"
        case messagePlaceholder = "message_placeholder"
        case initialMessage = "initial_message"
    }
}

public struct ResolveKitSDKCompat: Codable, Sendable, Equatable {
    public let minimumSDKVersion: String
    public let supportedSDKMajorVersions: [Int]
    public let clientRequirements: [String]
    public let serverTime: String

    enum CodingKeys: String, CodingKey {
        case minimumSDKVersion = "minimum_sdk_version"
        case supportedSDKMajorVersions = "supported_sdk_major_versions"
        case clientRequirements = "client_requirements"
        case serverTime = "server_time"
    }
}

public struct ResolveKitTurnAccepted: Codable, Sendable, Equatable {
    public let turnID: String
    public let requestID: String
    public let status: String

    enum CodingKeys: String, CodingKey {
        case turnID = "turn_id"
        case requestID = "request_id"
        case status
    }
}

public struct ResolveKitMessageRequest: Codable, Sendable {
    public let text: String
    public let requestID: String
    public let locale: String?

    public init(text: String, requestID: String, locale: String? = nil) {
        self.text = text
        self.requestID = requestID
        self.locale = locale
    }

    enum CodingKeys: String, CodingKey {
        case text
        case requestID = "request_id"
        case locale
    }
}

public struct ResolveKitToolResultRequest: Codable, Sendable {
    public let turnID: String
    public let idempotencyKey: String
    public let callID: String
    public let status: ResolveKitToolResultStatus
    public let result: JSONValue?
    public let error: String?

    public init(
        turnID: String,
        idempotencyKey: String,
        callID: String,
        status: ResolveKitToolResultStatus,
        result: JSONValue? = nil,
        error: String? = nil
    ) {
        self.turnID = turnID
        self.idempotencyKey = idempotencyKey
        self.callID = callID
        self.status = status
        self.result = result
        self.error = error
    }

    enum CodingKeys: String, CodingKey {
        case turnID = "turn_id"
        case idempotencyKey = "idempotency_key"
        case callID = "call_id"
        case status
        case result
        case error
    }
}

public struct ResolveKitSessionHistoryMessage: Codable, Sendable, Equatable {
    public let id: String
    public let role: String
    public let content: String?
    public let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case role
        case content
        case createdAt = "created_at"
    }
}

public final class ResolveKitAPIClient: Sendable {
    private static let chatCapabilityHeader = "X-Resolvekit-Chat-Capability"
    private let baseURL: URL
    private let apiKeyProvider: @Sendable () -> String?
    private let session: URLSession

    public init(baseURL: URL, apiKeyProvider: @escaping @Sendable () -> String?, session: URLSession? = nil) {
        self.baseURL = baseURL
        self.apiKeyProvider = apiKeyProvider
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.default
            configuration.timeoutIntervalForRequest = 15
            configuration.timeoutIntervalForResource = 30
            self.session = URLSession(configuration: configuration)
        }
    }

    func _debugAPIKey() -> String? {
        apiKeyProvider()
    }

    public func bulkSyncFunctions(_ functions: [ResolveKitDefinition]) async throws {
        struct RequestBody: Codable {
            let functions: [ResolveKitDefinition]
        }
        _ = try await request(
            path: "/v1/functions/bulk",
            method: "PUT",
            body: RequestBody(functions: functions),
            responseType: [ResolveKitRegisteredFunction].self
        )
    }

    public func listFunctions() async throws -> [ResolveKitRegisteredFunction] {
        try await request(path: "/v1/functions", method: "GET", body: Optional<String>.none, responseType: [ResolveKitRegisteredFunction].self)
    }

    public func createSession(_ requestBody: ResolveKitSessionCreateRequest) async throws -> ResolveKitSession {
        try await request(path: "/v1/sessions", method: "POST", body: requestBody, responseType: ResolveKitSession.self)
    }

    public func patchSessionContext(
        sessionID: String,
        chatCapabilityToken: String,
        requestBody: ResolveKitSessionContextPatchRequest
    ) async throws -> ResolveKitSessionContextOut {
        try await request(
            path: "/v1/sessions/\(sessionID)/context",
            method: "PATCH",
            body: requestBody,
            responseType: ResolveKitSessionContextOut.self,
            chatCapabilityToken: chatCapabilityToken
        )
    }

    public func sdkCompatibility() async throws -> ResolveKitSDKCompat {
        try await request(path: "/v1/sdk/compat", method: "GET", body: Optional<String>.none, responseType: ResolveKitSDKCompat.self)
    }

    public func chatTheme() async throws -> ResolveKitChatTheme {
        try await request(path: "/v1/sdk/chat-theme", method: "GET", body: Optional<String>.none, responseType: ResolveKitChatTheme.self)
    }

    public func sendMessage(
        sessionID: String,
        requestBody: ResolveKitMessageRequest,
        chatCapabilityToken: String
    ) async throws -> ResolveKitTurnAccepted {
        try await request(
            path: "/v1/sessions/\(sessionID)/messages",
            method: "POST",
            body: requestBody,
            responseType: ResolveKitTurnAccepted.self,
            chatCapabilityToken: chatCapabilityToken
        )
    }

    public func listSessionMessages(
        sessionID: String,
        chatCapabilityToken: String
    ) async throws -> [ResolveKitSessionHistoryMessage] {
        try await request(
            path: "/v1/sessions/\(sessionID)/messages",
            method: "GET",
            body: Optional<String>.none,
            responseType: [ResolveKitSessionHistoryMessage].self,
            chatCapabilityToken: chatCapabilityToken
        )
    }

    public func sessionLocalization(
        sessionID: String,
        locale: String?,
        chatCapabilityToken: String
    ) async throws -> ResolveKitSessionLocalization {
        guard let key = apiKeyProvider(), !key.isEmpty else {
            throw ResolveKitAPIClientError.missingAPIKey
        }
        var components = URLComponents(
            url: baseURL.resolveKitAppending(path: "/v1/sessions/\(sessionID)/localization"),
            resolvingAgainstBaseURL: false
        )
        if let locale, !locale.isEmpty {
            components?.queryItems = [URLQueryItem(name: "locale", value: locale)]
        }
        guard let url = components?.url else {
            throw ResolveKitAPIClientError.invalidResponse
        }

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(chatCapabilityToken, forHTTPHeaderField: Self.chatCapabilityHeader)

        ResolveKitNetworkLogger.log("Request GET /v1/sessions/\(sessionID)/localization payload={}")
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw ResolveKitAPIClientError.invalidResponse
        }
        let responseBody = String(data: data, encoding: .utf8) ?? "<unprintable>"
        ResolveKitNetworkLogger.log("Response GET /v1/sessions/\(sessionID)/localization status=\(http.statusCode)")
        guard (200...299).contains(http.statusCode) else {
            throw errorFromHTTPFailure(statusCode: http.statusCode, responseBody: responseBody)
        }
        return try JSONDecoder().decode(ResolveKitSessionLocalization.self, from: data)
    }

    public func buildEventsURL(relativePath: String, cursor: String? = nil) throws -> URL {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw ResolveKitAPIClientError.invalidResponse
        }
        components.path = relativePath
        if let cursor, !cursor.isEmpty {
            components.queryItems = [URLQueryItem(name: "cursor", value: cursor)]
        }
        guard let url = components.url else {
            throw ResolveKitAPIClientError.invalidResponse
        }
        return url
    }

    public func submitToolResult(
        sessionID: String,
        requestBody: ResolveKitToolResultRequest,
        chatCapabilityToken: String
    ) async throws {
        _ = try await request(
            path: "/v1/sessions/\(sessionID)/tool-results",
            method: "POST",
            body: requestBody,
            responseType: EmptyResponse.self,
            chatCapabilityToken: chatCapabilityToken
        )
    }

    public func authorizedURLRequest(path: String, method: String, chatCapabilityToken: String? = nil) throws -> URLRequest {
        guard let key = apiKeyProvider(), !key.isEmpty else {
            throw ResolveKitAPIClientError.missingAPIKey
        }
        let url = baseURL.resolveKitAppending(path: path)
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let chatCapabilityToken, !chatCapabilityToken.isEmpty {
            req.setValue(chatCapabilityToken, forHTTPHeaderField: Self.chatCapabilityHeader)
        }
        return req
    }

    private func request<Body: Encodable, Response: Decodable>(
        path: String,
        method: String,
        body: Body?,
        responseType: Response.Type,
        chatCapabilityToken: String? = nil
    ) async throws -> Response {
        var req = try authorizedURLRequest(path: path, method: method, chatCapabilityToken: chatCapabilityToken)
        var payloadString = "{}"
        if let body {
            let bodyData = try JSONEncoder().encode(body)
            req.httpBody = bodyData
            payloadString = "<redacted>"
        }

        ResolveKitNetworkLogger.log("Request \(method) \(path) payload=\(payloadString)")

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            ResolveKitNetworkLogger.log("Response \(method) \(path) invalid HTTP response")
            throw ResolveKitAPIClientError.invalidResponse
        }
        let responseBody = String(data: data, encoding: .utf8) ?? "<unprintable>"
        ResolveKitNetworkLogger.log("Response \(method) \(path) status=\(http.statusCode)")

        guard (200...299).contains(http.statusCode) else {
            let summary = debugServerErrorSummary(statusCode: http.statusCode, responseBody: responseBody)
            ResolveKitNetworkLogger.log("Failure \(method) \(path) \(summary)")
            if http.statusCode == 405 {
                throw ResolveKitAPIClientError.methodNotAllowed(
                    method: method,
                    path: path,
                    payload: payloadString,
                    response: responseBody
                )
            }
            throw errorFromHTTPFailure(statusCode: http.statusCode, responseBody: responseBody)
        }

        if Response.self == EmptyResponse.self {
            return EmptyResponse() as! Response
        }
        return try JSONDecoder().decode(Response.self, from: data)
    }

    func errorFromHTTPFailure(statusCode: Int, responseBody: String) -> ResolveKitAPIClientError {
        if parseChatUnavailableError(responseBody) {
            ResolveKitNetworkLogger.log("Mapped server error status=\(statusCode) to chat_unavailable")
            return .chatUnavailable
        }
        return .serverError(statusCode: statusCode, message: responseBody)
    }

    func debugServerErrorSummary(statusCode: Int, responseBody: String) -> String {
        let fallbackBody = responseBody.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = responseBody.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            if fallbackBody.isEmpty {
                return "status=\(statusCode)"
            }
            return "status=\(statusCode) body=\(fallbackBody)"
        }

        var parts = ["status=\(statusCode)"]
        if let code = extractErrorCode(object) {
            parts.append("code=\(code)")
        }
        if let message = extractErrorMessage(object) {
            parts.append("message=\(message)")
        }

        if parts.count == 1 && !fallbackBody.isEmpty {
            parts.append("body=\(fallbackBody)")
        }
        return parts.joined(separator: " ")
    }

    private func extractErrorCode(_ object: [String: Any]) -> String? {
        if let code = object["code"] as? String, !code.isEmpty {
            return code
        }
        if let detail = object["detail"] as? [String: Any],
           let code = detail["code"] as? String,
           !code.isEmpty {
            return code
        }
        return nil
    }

    private func extractErrorMessage(_ object: [String: Any]) -> String? {
        if let message = object["message"] as? String, !message.isEmpty {
            return message
        }
        if let detailText = object["detail"] as? String, !detailText.isEmpty {
            return detailText
        }
        if let detail = object["detail"] as? [String: Any] {
            if let message = detail["message"] as? String, !message.isEmpty {
                return message
            }
            if let nestedDetail = detail["detail"] as? String, !nestedDetail.isEmpty {
                return nestedDetail
            }
        }
        return nil
    }

    private func parseChatUnavailableError(_ responseBody: String) -> Bool {
        guard let data = responseBody.data(using: .utf8) else {
            return false
        }

        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }
        if let code = object["code"] as? String, code == "chat_unavailable" {
            return true
        }
        if let detail = object["detail"] as? [String: Any],
           let code = detail["code"] as? String,
           code == "chat_unavailable" {
            return true
        }
        return false
    }
}

private extension URL {
    func resolveKitAppending(path: String) -> URL {
        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: false) else {
            let trimmedPath = path.hasPrefix("/") ? String(path.dropFirst()) : path
            return appendingPathComponent(trimmedPath)
        }

        let suffix = path.hasPrefix("/") ? path : "/" + path
        let basePath = components.path.hasSuffix("/") ? String(components.path.dropLast()) : components.path
        components.path = basePath + suffix
        return components.url ?? self
    }
}

public struct ResolveKitRegisteredFunction: Codable, Sendable, Equatable {
    public let id: String
    public let appID: String
    public let name: String
    public let description: String
    public let isActive: Bool
    public let timeoutSeconds: Int

    enum CodingKeys: String, CodingKey {
        case id
        case appID = "app_id"
        case name
        case description
        case isActive = "is_active"
        case timeoutSeconds = "timeout_seconds"
    }
}

private struct EmptyResponse: Codable {}
