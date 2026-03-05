import Foundation
import ResolveKitCore

private enum ResolveKitWebSocketLogger {
    static func log(_ message: String) {
        print("[ResolveKit][WS] \(message)")
    }
}

public actor ResolveKitWebSocketClient {
    public enum Event: Sendable {
        case connected
        case disconnected
        case envelope(ResolveKitEnvelope)
        case failed(String)
    }

    private let session: URLSession
    private var task: URLSessionWebSocketTask?
    private var continuation: AsyncStream<Event>.Continuation?

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func connect(url: URL) -> AsyncStream<Event> {
        AsyncStream<Event> { continuation in
            Task {
                ResolveKitWebSocketLogger.log("Connect \(url.host ?? "unknown-host")\(url.path)")
                self.continuation = continuation
                let task = self.session.webSocketTask(with: url)
                self.task = task
                task.resume()
                continuation.yield(.connected)
                await self.listen(task: task)
            }
        }
    }

    public func disconnect() {
        ResolveKitWebSocketLogger.log("Disconnect")
        task?.cancel(with: .normalClosure, reason: nil)
        continuation?.yield(.disconnected)
        continuation?.finish()
        task = nil
        continuation = nil
    }

    public func send(envelope: ResolveKitEnvelope) async throws {
        guard let task else {
            throw ResolveKitAPIClientError.invalidResponse
        }
        let data = try JSONEncoder().encode(envelope)
        guard let text = String(data: data, encoding: .utf8) else {
            throw ResolveKitAPIClientError.invalidResponse
        }
        _ = text
        ResolveKitWebSocketLogger.log("Send type=\(envelope.type)")
        try await task.send(.string(text))
    }

    public func sendChatMessage(text: String, locale: String? = nil, requestID: String? = nil) async throws {
        var payload: JSONObject = ["text": .string(text)]
        if let locale, !locale.isEmpty {
            payload["locale"] = .string(locale)
        }
        let envelope = ResolveKitEnvelope(
            type: "chat_message",
            requestID: requestID,
            payload: payload,
            timestamp: ISO8601DateFormatter().string(from: Date())
        )
        try await send(envelope: envelope)
    }

    public func sendToolResult(_ payload: ResolveKitToolResultPayload, requestID: String? = nil) async throws {
        let data = try JSONEncoder().encode(payload)
        let jsonPayload = try JSONDecoder().decode(JSONObject.self, from: data)
        let envelope = ResolveKitEnvelope(
            type: "tool_result",
            requestID: requestID,
            payload: jsonPayload,
            timestamp: ISO8601DateFormatter().string(from: Date())
        )
        try await send(envelope: envelope)
    }

    public func ping() async throws {
        let envelope = ResolveKitEnvelope(type: "ping", payload: [:], timestamp: ISO8601DateFormatter().string(from: Date()))
        try await send(envelope: envelope)
    }

    public func sendPong() async throws {
        let envelope = ResolveKitEnvelope(type: "pong", payload: [:], timestamp: ISO8601DateFormatter().string(from: Date()))
        try await send(envelope: envelope)
    }

    private func listen(task: URLSessionWebSocketTask) async {
        do {
            let message = try await task.receive()
            let envelope: ResolveKitEnvelope
            switch message {
            case .string(let text):
                guard let data = text.data(using: .utf8) else {
                    continuation?.yield(.failed("Failed to decode text frame"))
                    await listen(task: task)
                    return
                }
                envelope = try JSONDecoder().decode(ResolveKitEnvelope.self, from: data)
            case .data(let data):
                envelope = try JSONDecoder().decode(ResolveKitEnvelope.self, from: data)
                _ = data.count
            @unknown default:
                continuation?.yield(.failed("Unknown websocket message"))
                await listen(task: task)
                return
            }

            ResolveKitWebSocketLogger.log("Receive type=\(envelope.type)")
            continuation?.yield(.envelope(envelope))
            await listen(task: task)
        } catch {
            ResolveKitWebSocketLogger.log("Receive error: \(error.localizedDescription)")
            continuation?.yield(.failed(error.localizedDescription))
            continuation?.finish()
            self.task = nil
        }
    }
}
