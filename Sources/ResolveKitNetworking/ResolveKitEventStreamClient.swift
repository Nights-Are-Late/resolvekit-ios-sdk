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

    public init(apiClient: ResolveKitAPIClient, session: URLSession = .shared) {
        self.apiClient = apiClient
        self.session = session
    }

    public func stream(
        eventsPath: String,
        chatCapabilityToken: String,
        cursor: String?
    ) async throws -> AsyncThrowingStream<ResolveKitEventStreamEvent, Error> {
        let url = try apiClient.buildEventsURL(relativePath: eventsPath, cursor: cursor)
        var request = URLRequest(url: url)
        guard let apiKey = apiClient._debugAPIKey() else {
            throw ResolveKitAPIClientError.missingAPIKey
        }
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(chatCapabilityToken, forHTTPHeaderField: "X-Resolvekit-Chat-Capability")

        ResolveKitEventStreamLogger.log("Request GET \(url.path)")
        let (bytes, response) = try await session.bytes(for: request)
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

                    for try await line in bytes.lines {
                        if line.isEmpty {
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
                            currentEventID = line.replacingOccurrences(of: "id:", with: "").trimmingCharacters(in: .whitespaces)
                        } else if line.hasPrefix("data:") {
                            dataBuffer += line.replacingOccurrences(of: "data:", with: "").trimmingCharacters(in: .whitespaces)
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
