import Foundation
import ResolveKitCore

private enum ResolveKitEventStreamLogger {
    static func log(_ message: String) {
        print("[ResolveKit][Events] \(message)")
    }
}

public struct ResolveKitEventStreamEvent: Sendable {
    public let id: String?
    public let envelope: ResolveKitEnvelope
}

public final class ResolveKitEventStreamClient: Sendable {
    private let apiClient: ResolveKitAPIClient
    private let session: URLSession
    private static let longLivedTimeout: TimeInterval = 7 * 24 * 60 * 60

    public init(apiClient: ResolveKitAPIClient, session: URLSession = .shared) {
        self.apiClient = apiClient
        if session == .shared {
            let configuration = URLSessionConfiguration.default
            configuration.timeoutIntervalForRequest = Self.longLivedTimeout
            configuration.timeoutIntervalForResource = Self.longLivedTimeout
            configuration.waitsForConnectivity = true
            self.session = URLSession(configuration: configuration)
        } else {
            self.session = session
        }
    }

    public func stream(
        eventsPath: String,
        chatCapabilityToken: String,
        cursor: String?,
        onHeartbeat: (@Sendable () -> Void)? = nil
    ) async throws -> AsyncThrowingStream<ResolveKitEventStreamEvent, Error> {
        let url = try apiClient.buildEventsURL(relativePath: eventsPath, cursor: cursor)
        var request = URLRequest(url: url)
        guard let apiKey = apiClient._debugAPIKey() else {
            throw ResolveKitAPIClientError.missingAPIKey
        }
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue(chatCapabilityToken, forHTTPHeaderField: "X-Resolvekit-Chat-Capability")
        request.timeoutInterval = Self.longLivedTimeout

        ResolveKitEventStreamLogger.log("Request GET \(url.path) timeoutInterval=\(request.timeoutInterval)")
        let (bytes, response) = try await session.bytes(for: request)
        ResolveKitEventStreamLogger.log("Response received, status=\((response as? HTTPURLResponse)?.statusCode ?? -1)")
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            if let http = response as? HTTPURLResponse {
                var body = ""
                for try await line in bytes.lines {
                    body += line
                }
                throw apiClient.errorFromHTTPFailure(statusCode: http.statusCode, responseBody: body)
            }
            throw ResolveKitAPIClientError.invalidResponse
        }

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    var currentEventID: String?
                    var dataBuffer = ""
                    var lineBuffer = Data()

                    for try await byte in bytes {
                        onHeartbeat?()

                        if byte == UInt8(ascii: "\n") {
                            let line = String(data: lineBuffer, encoding: .utf8) ?? ""
                            lineBuffer.removeAll(keepingCapacity: true)

                            if line.isEmpty {
                                // Empty line = end of SSE event
                                if !dataBuffer.isEmpty {
                                    let data = Data(dataBuffer.utf8)
                                    let envelope = try JSONDecoder().decode(ResolveKitEnvelope.self, from: data)
                                    continuation.yield(ResolveKitEventStreamEvent(id: currentEventID, envelope: envelope))
                                }
                                currentEventID = nil
                                dataBuffer = ""
                                continue
                            }

                            if line.hasPrefix("id:") {
                                currentEventID = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                            } else if line.hasPrefix("data:") {
                                dataBuffer += String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                            }
                            // Comments (": ...") and "event:" lines are silently consumed
                        } else {
                            lineBuffer.append(byte)
                        }
                    }

                    continuation.finish()
                } catch {
                    ResolveKitEventStreamLogger.log("Stream error: \(error.localizedDescription)")
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}

#if DEBUG
extension ResolveKitEventStreamClient {
    func _debugSessionConfiguration() -> URLSessionConfiguration {
        session.configuration
    }
}
#endif
