import Foundation
import Security
import ResolveKitCore

private enum ResolveKitWebSocketLogger {
    static func log(_ message: String) {
        print("[ResolveKit][WS] \(message)")
    }
}

/// Shared delegate for all SDK URLSessions. Handles server trust challenges
/// so connections succeed behind VPNs / corporate proxies that perform TLS
/// inspection. Also bridges `didOpenWithProtocol` for the WebSocket client.
final class ResolveKitSessionDelegate: NSObject, URLSessionWebSocketDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var _onOpen: (() -> Void)?

    private static func log(_ message: String) {
        print("[ResolveKit][TLS] \(message)")
    }

    func setOnOpen(_ handler: (() -> Void)?) {
        lock.lock()
        _onOpen = handler
        lock.unlock()
    }

    // MARK: - Server trust (session-level)

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        handleServerTrustChallenge(challenge, completionHandler: completionHandler)
    }

    // MARK: - Server trust (task-level, fires when session-level is skipped)

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        handleServerTrustChallenge(challenge, completionHandler: completionHandler)
    }

    private func handleServerTrustChallenge(
        _ challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        let host = challenge.protectionSpace.host
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust else {
            Self.log("Auth challenge for \(host): non-server-trust, default handling")
            completionHandler(.performDefaultHandling, nil)
            return
        }

        var error: CFError?
        if SecTrustEvaluateWithError(serverTrust, &error) {
            Self.log("Trust OK for \(host)")
        } else {
            let desc = (error as Error?)?.localizedDescription ?? "unknown"
            Self.log("Trust evaluation failed for \(host): \(desc) – accepting anyway (VPN/proxy)")
        }
        completionHandler(.useCredential, URLCredential(trust: serverTrust))
    }

    // MARK: - WebSocket lifecycle

    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didOpenWithProtocol protocol: String?
    ) {
        ResolveKitWebSocketLogger.log("didOpenWithProtocol: \(`protocol` ?? "none")")
        lock.lock()
        let handler = _onOpen
        _onOpen = nil
        lock.unlock()
        handler?()
    }
}

public actor ResolveKitWebSocketClient {
    public enum Event: Sendable {
        case connected
        case disconnected
        case envelope(ResolveKitEnvelope)
        case failed(String)
    }

    private var session: URLSession
    private var sessionDelegate: ResolveKitSessionDelegate?
    private var customSession: Bool
    private var task: URLSessionWebSocketTask?
    private var continuation: AsyncStream<Event>.Continuation?

    public init(session: URLSession? = nil) {
        if let session {
            self.customSession = true
            self.sessionDelegate = nil
            self.session = session
        } else {
            self.customSession = false
            let delegate = ResolveKitSessionDelegate()
            self.sessionDelegate = delegate
            self.session = URLSession(
                configuration: .default,
                delegate: delegate,
                delegateQueue: nil
            )
        }
    }

    /// Invalidates the current URLSession and creates a fresh one, clearing
    /// any cached TLS session tickets that become stale after a VPN / network
    /// path change. When `forceTLS12` is true the new session caps TLS at 1.2,
    /// working around VPN proxies that reject TLS 1.3 ClientHello.
    /// No-op when a custom session was injected.
    public func resetSession(forceTLS12: Bool = false) {
        guard !customSession else { return }
        sessionDelegate?.setOnOpen(nil)
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        continuation?.finish()
        continuation = nil
        session.invalidateAndCancel()
        let delegate = ResolveKitSessionDelegate()
        sessionDelegate = delegate
        let configuration = URLSessionConfiguration.default
        if forceTLS12 {
            configuration.tlsMinimumSupportedProtocolVersion = .TLSv12
            configuration.tlsMaximumSupportedProtocolVersion = .TLSv12
        }
        session = URLSession(
            configuration: configuration,
            delegate: delegate,
            delegateQueue: nil
        )
        ResolveKitWebSocketLogger.log("Session reset\(forceTLS12 ? " (TLS 1.2 only)" : "") – TLS cache cleared")
    }

    public func connect(url: URL) -> AsyncStream<Event> {
        AsyncStream<Event> { continuation in
            Task {
                ResolveKitWebSocketLogger.log("Connect \(url.host ?? "unknown-host")\(url.path)")
                self.continuation = continuation

                if let delegate = self.sessionDelegate {
                    delegate.setOnOpen {
                        ResolveKitWebSocketLogger.log("Open confirmed by delegate")
                        continuation.yield(.connected)
                    }
                }

                let task = self.session.webSocketTask(with: url)
                self.task = task
                task.resume()

                if self.sessionDelegate == nil {
                    continuation.yield(.connected)
                }

                await self.listen(task: task, continuation: continuation)
            }
        }
    }

    public func disconnect() {
        ResolveKitWebSocketLogger.log("Disconnect")
        sessionDelegate?.setOnOpen(nil)
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

    private func listen(task: URLSessionWebSocketTask, continuation: AsyncStream<Event>.Continuation) async {
        do {
            let message = try await task.receive()
            let envelope: ResolveKitEnvelope
            switch message {
            case .string(let text):
                guard let data = text.data(using: .utf8) else {
                    continuation.yield(.failed("Failed to decode text frame"))
                    await listen(task: task, continuation: continuation)
                    return
                }
                envelope = try JSONDecoder().decode(ResolveKitEnvelope.self, from: data)
            case .data(let data):
                envelope = try JSONDecoder().decode(ResolveKitEnvelope.self, from: data)
                _ = data.count
            @unknown default:
                continuation.yield(.failed("Unknown websocket message"))
                await listen(task: task, continuation: continuation)
                return
            }

            ResolveKitWebSocketLogger.log("Receive type=\(envelope.type)")
            continuation.yield(.envelope(envelope))
            await listen(task: task, continuation: continuation)
        } catch {
            ResolveKitWebSocketLogger.log("Receive error: \(error.localizedDescription)")
            continuation.yield(.failed(error.localizedDescription))
            continuation.finish()
            if self.task === task {
                self.task = nil
            }
        }
    }
}
