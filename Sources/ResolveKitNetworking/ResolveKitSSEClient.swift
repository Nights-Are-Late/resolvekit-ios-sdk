import Foundation
import ResolveKitCore

private enum ResolveKitSSELogger {
    static func log(_ message: String) {
        print("[ResolveKit][SSE] \(message)")
    }
}

public struct ResolveKitSSEEvent: Sendable {
    public let name: String
    public let payload: JSONObject
}

public final class ResolveKitSSEClient: Sendable {
    private let apiClient: ResolveKitAPIClient
    private let session: URLSession

    public init(apiClient: ResolveKitAPIClient, session: URLSession = .shared) {
        self.apiClient = apiClient
        self.session = session
    }

    public func stream(
        sessionID: String,
        text: String,
        locale: String?,
        chatCapabilityToken: String
    ) async throws -> AsyncThrowingStream<ResolveKitSSEEvent, Error> {
        var request = try apiClient.authorizedURLRequest(
            path: "/v1/sessions/\(sessionID)/messages",
            method: "POST",
            chatCapabilityToken: chatCapabilityToken
        )
        var payload: [String: String] = ["text": text]
        if let locale, !locale.isEmpty {
            payload["locale"] = locale
        }
        let body = try JSONEncoder().encode(payload)
        request.httpBody = body
        ResolveKitSSELogger.log("Request POST /v1/sessions/\(sessionID)/messages payload=<redacted>")

        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            if let http = response as? HTTPURLResponse {
                ResolveKitSSELogger.log("Response POST /v1/sessions/\(sessionID)/messages status=\(http.statusCode)")
                var body = ""
                do {
                    for try await line in bytes.lines {
                        body += line
                    }
                } catch {
                    throw ResolveKitAPIClientError.invalidResponse
                }
                throw apiClient.errorFromHTTPFailure(statusCode: http.statusCode, responseBody: body)
            }
            throw ResolveKitAPIClientError.invalidResponse
        }
        ResolveKitSSELogger.log("Response POST /v1/sessions/\(sessionID)/messages status=\(http.statusCode)")

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    var eventName = ""
                    var dataBuffer = ""

                    for try await line in bytes.lines {
                        if line.isEmpty {
                            if !eventName.isEmpty {
                                let payloadData = Data(dataBuffer.utf8)
                                let payload = try JSONDecoder().decode(JSONObject.self, from: payloadData)
                                ResolveKitSSELogger.log("Event \(eventName)")
                                continuation.yield(ResolveKitSSEEvent(name: eventName, payload: payload))
                            }
                            eventName = ""
                            dataBuffer = ""
                            continue
                        }

                        if line.hasPrefix("event:") {
                            eventName = line.replacingOccurrences(of: "event:", with: "").trimmingCharacters(in: .whitespaces)
                        } else if line.hasPrefix("data:") {
                            dataBuffer += line.replacingOccurrences(of: "data:", with: "").trimmingCharacters(in: .whitespaces)
                        }
                    }

                    continuation.finish()
                } catch {
                    ResolveKitSSELogger.log("Stream error: \(error.localizedDescription)")
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    public func submitToolResult(
        sessionID: String,
        payload: ResolveKitToolResultPayload,
        chatCapabilityToken: String
    ) async throws {
        var request = try apiClient.authorizedURLRequest(
            path: "/v1/sessions/\(sessionID)/tool-results",
            method: "POST",
            chatCapabilityToken: chatCapabilityToken
        )
        let body = try JSONEncoder().encode(payload)
        request.httpBody = body
        ResolveKitSSELogger.log("Request POST /v1/sessions/\(sessionID)/tool-results payload=<redacted>")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            if let http = response as? HTTPURLResponse {
                ResolveKitSSELogger.log("Response POST /v1/sessions/\(sessionID)/tool-results status=\(http.statusCode)")
                let responseBody = String(data: data, encoding: .utf8) ?? ""
                throw apiClient.errorFromHTTPFailure(statusCode: http.statusCode, responseBody: responseBody)
            }
            throw ResolveKitAPIClientError.invalidResponse
        }
        ResolveKitSSELogger.log("Response POST /v1/sessions/\(sessionID)/tool-results status=\(http.statusCode)")
    }
}
