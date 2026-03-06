import Foundation
import SwiftUI
import Testing
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif
@testable import ResolveKitCore
@testable import ResolveKitNetworking
@testable import ResolveKitUI

/// Integration tests verify the full function registration → dispatch pipeline.
@Suite("Integration: registry + dispatch")
struct ResolveKitIntegrationTests {

    @Test("Register multiple functions and retrieve definitions")
    func multipleDefinitions() async throws {
        let registry = ResolveKitRegistry()
        try await registry.register([LightsFunction.self, WeatherFunction.self])
        let defs = await registry.definitions
        #expect(defs.count == 2)
        #expect(defs.map(\.name).contains("set_lights"))
        #expect(defs.map(\.name).contains("get_weather"))
    }

    @Test("Dispatch lights function")
    func dispatchLights() async throws {
        let registry = ResolveKitRegistry()
        try await registry.register(LightsFunction.self)
        let ctx = ResolveKitFunctionContext(sessionID: "s", requestID: nil)
        let result = try await registry.dispatch(
            functionName: "set_lights",
            arguments: ["room": .string("living room"), "on": .bool(true)],
            context: ctx
        )
        if case .object(let obj) = result {
            #expect(obj["brightness"] == .number(100))
        } else {
            Issue.record("Expected object result")
        }
    }

    @Test("Dispatch weather function")
    func dispatchWeather() async throws {
        let registry = ResolveKitRegistry()
        try await registry.register(WeatherFunction.self)
        let ctx = ResolveKitFunctionContext(sessionID: "s", requestID: nil)
        let result = try await registry.dispatch(
            functionName: "get_weather",
            arguments: ["city": .string("London")],
            context: ctx
        )
        if case .object(let obj) = result {
            #expect(obj["condition"] == .string("sunny"))
        } else {
            Issue.record("Expected object result")
        }
    }

    @Test("Session decodes chat capability token")
    func sessionDecodesChatCapabilityToken() throws {
        let payload = """
        {
          "id": "8beeaed0-c3f5-44da-a55f-57a3624f760f",
          "events_url": "/v1/sessions/8beeaed0-c3f5-44da-a55f-57a3624f760f/events",
          "chat_capability_token": "opaque-token",
          "available_function_names": ["set_lights", "get_weather"],
          "locale": "fr",
          "chat_title": "Assistance",
          "message_placeholder": "Message",
          "initial_message": "Bonjour"
        }
        """
        let data = Data(payload.utf8)
        let session = try JSONDecoder().decode(ResolveKitSession.self, from: data)
        #expect(session.chatCapabilityToken == "opaque-token")
        #expect(session.eventsURL == "/v1/sessions/8beeaed0-c3f5-44da-a55f-57a3624f760f/events")
        #expect(session.reusedActiveSession == false)
        #expect(session.locale == "fr")
        #expect(session.chatTitle == "Assistance")
        #expect(session.availableFunctionNames == ["set_lights", "get_weather"])
    }

    @Test("Session decodes reused active session marker")
    func sessionDecodesReusedActiveSessionMarker() throws {
        let payload = """
        {
          "id": "8beeaed0-c3f5-44da-a55f-57a3624f760f",
          "events_url": "/v1/sessions/8beeaed0-c3f5-44da-a55f-57a3624f760f/events",
          "chat_capability_token": "opaque-token",
          "reused_active_session": true
        }
        """
        let data = Data(payload.utf8)
        let session = try JSONDecoder().decode(ResolveKitSession.self, from: data)
        #expect(session.reusedActiveSession == true)
        #expect(session.availableFunctionNames.isEmpty)

    }
}

@Suite("Networking: debug error summaries")
struct ResolveKitNetworkingDebugTests {

    @Test("Summarizes invalid API key responses")
    func summarizesInvalidAPIKeyResponse() {
        let client = ResolveKitAPIClient(
            baseURL: URL(string: "http://localhost:8000")!,
            apiKeyProvider: { "iaa_test_key" }
        )
        let summary = client.debugServerErrorSummary(
            statusCode: 401,
            responseBody: #"{"detail":"Invalid API key"}"#
        )
        #expect(summary.contains("status=401"))
        #expect(summary.contains("message=Invalid API key"))
    }

    @Test("Summarizes chat unavailable code responses")
    func summarizesChatUnavailableCodeResponse() {
        let client = ResolveKitAPIClient(
            baseURL: URL(string: "http://localhost:8000")!,
            apiKeyProvider: { "iaa_test_key" }
        )
        let summary = client.debugServerErrorSummary(
            statusCode: 403,
            responseBody: #"{"detail":{"code":"chat_unavailable","message":"Chat is unavailable, try again later"}}"#
        )
        #expect(summary.contains("status=403"))
        #expect(summary.contains("code=chat_unavailable"))
        #expect(summary.contains("message=Chat is unavailable, try again later"))
    }

    @Test("Session create request encodes llm_context")
    func sessionCreateRequestEncodesLLMContext() throws {
        let request = ResolveKitSessionCreateRequest(
            deviceID: "device-1",
            client: ["platform": "ios"],
            llmContext: [
                "location": .object([
                    "city": .string("Vilnius"),
                    "country": .string("LT")
                ]),
                "network_type": .string("wifi"),
                "is_traveling": .bool(false)
            ],
            availableFunctionNames: ["set_lights", "get_weather"],
            locale: "fr",
            preferredLocales: ["fr-FR", "en-US"]
        )

        let data = try JSONEncoder().encode(request)
        let object = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        #expect(object["metadata"] == nil)
        #expect(object["entitlements"] == nil)
        #expect(object["capabilities"] == nil)
        #expect(object["available_function_names"] as? [String] == ["set_lights", "get_weather"])
        let llmContext = try #require(object["llm_context"] as? [String: Any])
        #expect(llmContext["network_type"] as? String == "wifi")
        #expect(llmContext["is_traveling"] as? Bool == false)
        let location = try #require(llmContext["location"] as? [String: Any])
        #expect(location["city"] as? String == "Vilnius")
        #expect(object["locale"] as? String == "fr")
        #expect(object["preferred_locales"] as? [String] == ["fr-FR", "en-US"])
        #expect(object["reuse_active_session"] as? Bool == true)
    }

    @Test("Session context patch request encodes available function allowlist")
    func sessionContextPatchRequestEncodesAllowlist() throws {
        let request = ResolveKitSessionContextPatchRequest(
            client: ["platform": "ios"],
            llmContext: ["network_type": .string("cellular")],
            availableFunctionNames: ["set_lights"],
            locale: "fr"
        )

        let data = try JSONEncoder().encode(request)
        let object = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        #expect(object["available_function_names"] as? [String] == ["set_lights"])
        #expect(object["locale"] as? String == "fr")
        let llmContext = try #require(object["llm_context"] as? [String: Any])
        #expect(llmContext["network_type"] as? String == "cellular")
    }

    @Test("Session history message decodes core fields")
    func sessionHistoryMessageDecodesCoreFields() throws {
        let payload = """
        {
          "id": "6edca6c2-b4a7-4f5f-b3c8-d9f1880f2281",
          "session_id": "8beeaed0-c3f5-44da-a55f-57a3624f760f",
          "sequence_number": 3,
          "role": "assistant",
          "content": "Use settings screen",
          "tool_calls": null,
          "tool_call_id": null,
          "token_count": null,
          "created_at": "2026-02-26T18:21:10.000000+00:00"
        }
        """
        let data = Data(payload.utf8)
        let message = try JSONDecoder().decode(ResolveKitSessionHistoryMessage.self, from: data)
        #expect(message.role == "assistant")
        #expect(message.content == "Use settings screen")
        #expect(message.createdAt == "2026-02-26T18:21:10.000000+00:00")
    }

    @Test("Chat theme decodes from sdk endpoint shape")
    func chatThemeDecodesFromResponse() throws {
        let payload = """
        {
          "light": {
            "screenBackground": "#F7F7FA",
            "titleText": "#111827",
            "statusText": "#4B5563",
            "composerBackground": "#FFFFFF",
            "composerText": "#111827",
            "composerPlaceholder": "#9CA3AF",
            "userBubbleBackground": "#DBEAFE",
            "userBubbleText": "#1E3A8A",
            "assistantBubbleBackground": "#E5E7EB",
            "assistantBubbleText": "#111827",
            "loaderBubbleBackground": "#E5E7EB",
            "loaderDotActive": "#374151",
            "loaderDotInactive": "#9CA3AF",
            "toolCardBackground": "#FFFFFFCC",
            "toolCardBorder": "#D1D5DB",
            "toolCardTitle": "#111827",
            "toolCardBody": "#374151"
          },
          "dark": {
            "screenBackground": "#0B0C10",
            "titleText": "#E5E7EB",
            "statusText": "#9CA3AF",
            "composerBackground": "#111318",
            "composerText": "#E5E7EB",
            "composerPlaceholder": "#6B7280",
            "userBubbleBackground": "#1E3A8A99",
            "userBubbleText": "#DBEAFE",
            "assistantBubbleBackground": "#1F2937",
            "assistantBubbleText": "#E5E7EB",
            "loaderBubbleBackground": "#1F2937",
            "loaderDotActive": "#E5E7EB",
            "loaderDotInactive": "#6B7280",
            "toolCardBackground": "#111318CC",
            "toolCardBorder": "#374151",
            "toolCardTitle": "#E5E7EB",
            "toolCardBody": "#9CA3AF"
          }
        }
        """
        let theme = try JSONDecoder().decode(ResolveKitChatTheme.self, from: Data(payload.utf8))
        #expect(theme.light.userBubbleBackground == "#DBEAFE")
        #expect(theme.dark.screenBackground == "#0B0C10")
    }
}

@Suite("Runtime: batched tool-call checklist")
struct ResolveKitRuntimeBatchTests {

    @Test("Rapid tool requests are grouped into one checklist")
    @MainActor
    func coalescesRapidToolCallsIntoSingleBatch() async {
        let runtime = makeRuntime()
        runtime._debugSetTurnInProgress(true)

        runtime._debugReceiveToolCallRequest(toolRequest(callID: "call-1", function: "set_lights"))
        runtime._debugReceiveToolCallRequest(toolRequest(callID: "call-2", function: "set_lights"))
        runtime._debugReceiveToolCallRequest(toolRequest(callID: "call-3", function: "set_lights"))
        await runtime._debugWaitForCoalescingWindow()

        #expect(runtime.toolCallChecklist.count == 3)
        #expect(runtime.toolCallBatchState == .awaitingApproval)
        #expect(runtime.toolCallChecklist.allSatisfy { $0.status == .pendingApproval })
    }

    @Test("Approve all runs each request and keeps mixed statuses")
    @MainActor
    func approveAllProducesMixedStatuses() async throws {
        let runtime = makeRuntime()
        try await runtime._debugRegisterFunctions([LightsFunction.self])
        runtime._debugSetTurnInProgress(true)

        runtime._debugReceiveToolCallRequest(toolRequest(callID: "ok", function: "set_lights"))
        runtime._debugReceiveToolCallRequest(toolRequest(callID: "bad", function: "does_not_exist"))
        await runtime._debugWaitForCoalescingWindow()
        await runtime.approveToolCallBatch()

        let byID = Dictionary(uniqueKeysWithValues: runtime.toolCallChecklist.map { ($0.id, $0.status) })
        #expect(byID["ok"] == .completed)
        #expect(byID["bad"] == .failed(error: "Unknown function: does_not_exist"))
        #expect(runtime.toolCallBatchState == .finished)
    }

    @Test("Decline all cancels every pending request")
    @MainActor
    func declineAllCancelsAllRows() async {
        let runtime = makeRuntime()
        runtime._debugSetTurnInProgress(true)

        runtime._debugReceiveToolCallRequest(toolRequest(callID: "deny-1", function: "set_lights"))
        runtime._debugReceiveToolCallRequest(toolRequest(callID: "deny-2", function: "set_lights"))
        await runtime._debugWaitForCoalescingWindow()
        await runtime.declineToolCallBatch()

        #expect(runtime.toolCallChecklist.allSatisfy { $0.status == .cancelled(reason: "User denied action") })
        #expect(runtime.toolCallBatchState == .finished)
    }

    @Test("Timeout marks request cancelled with timeout reason")
    @MainActor
    func timeoutMarksCancelled() async throws {
        let runtime = makeRuntime()
        try await runtime._debugRegisterFunctions([SlowFunction.self])
        runtime._debugSetTurnInProgress(true)

        runtime._debugReceiveToolCallRequest(
            ResolveKitToolCallRequest(
                callID: "timeout-1",
                functionName: "slow_function",
                arguments: [:],
                timeoutSeconds: 1,
                humanDescription: "Slow call"
            )
        )
        await runtime._debugWaitForCoalescingWindow()
        await runtime.approveToolCallBatch()

        guard let status = runtime.toolCallChecklist.first?.status else {
            Issue.record("Expected checklist item")
            return
        }
        switch status {
        case .cancelled(let reason):
            #expect(reason == "Timed out after 1s")
        default:
            Issue.record("Expected cancelled timeout status")
        }
    }

    @Test("Late request after first approval becomes a new batch")
    @MainActor
    func lateToolCallRequiresSecondBatchApproval() async throws {
        let runtime = makeRuntime()
        try await runtime._debugRegisterFunctions([LightsFunction.self])
        runtime._debugSetTurnInProgress(true)

        runtime._debugReceiveToolCallRequest(toolRequest(callID: "first", function: "set_lights"))
        await runtime._debugWaitForCoalescingWindow()
        await runtime.approveToolCallBatch()
        #expect(runtime.toolCallChecklist.count == 1)
        #expect(runtime.toolCallChecklist.first?.status == .completed)

        runtime._debugReceiveToolCallRequest(toolRequest(callID: "second", function: "set_lights"))
        await runtime._debugWaitForCoalescingWindow()

        #expect(runtime.toolCallBatchState == .awaitingApproval)
        #expect(runtime.toolCallChecklist.count == 1)
        #expect(runtime.toolCallChecklist.first?.id == "second")
        #expect(runtime.toolCallChecklist.first?.status == .pendingApproval)
    }

    @Test("Turn complete keeps finished checklist visible")
    @MainActor
    func turnCompletePreservesChecklistByDefault() async throws {
        let runtime = makeRuntime()
        try await runtime._debugRegisterFunctions([LightsFunction.self])
        runtime._debugSetTurnInProgress(true)

        runtime._debugReceiveToolCallRequest(toolRequest(callID: "done", function: "set_lights"))
        await runtime._debugWaitForCoalescingWindow()
        await runtime.approveToolCallBatch()
        runtime._debugHandleTurnComplete(fullText: "Completed.")

        #expect(runtime.isTurnInProgress == false)
        #expect(runtime.toolCallChecklist.count == 1)
        #expect(runtime.toolCallChecklist.first?.status == .completed)
    }

    @Test("Turn complete marks unapproved tool requests as timed out")
    @MainActor
    func turnCompleteMarksAwaitingAsTimedOut() async {
        let runtime = makeRuntime()
        runtime._debugSetTurnInProgress(true)

        runtime._debugReceiveToolCallRequest(toolRequest(callID: "awaiting-1", function: "set_lights"))
        await runtime._debugWaitForCoalescingWindow()
        runtime._debugHandleTurnComplete(fullText: "Timed out.")

        #expect(runtime.toolCallBatchState == .finished)
        guard let status = runtime.toolCallChecklist.first?.status else {
            Issue.record("Expected one tool checklist row")
            return
        }
        switch status {
        case .cancelled(let reason):
            #expect(reason == "Timed out")
        default:
            Issue.record("Expected cancelled status after turn completion timeout")
        }
    }

    @Test("Resetting tool call flow clears tool batch timeline")
    @MainActor
    func resetToolCallFlowClearsBatchHistory() async {
        let runtime = makeRuntime()
        runtime._debugSetTurnInProgress(true)

        runtime._debugReceiveToolCallRequest(toolRequest(callID: "stale-1", function: "set_lights"))
        await runtime._debugWaitForCoalescingWindow()
        #expect(runtime.toolCallBatches.count == 1)

        runtime._debugResetToolCallFlowForNewTurn()

        #expect(runtime.toolCallChecklist.isEmpty)
        #expect(runtime.toolCallBatches.isEmpty)
        #expect(runtime.toolCallBatchState == .idle)
    }

    @Test("chat unavailable frame shows generic assistant message")
    @MainActor
    func chatUnavailableFrameShowsAssistantFallback() async {
        let runtime = makeRuntime()
        runtime._debugSetTurnInProgress(true)

        let envelope = ResolveKitEnvelope(
            type: "error",
            payload: [
                "code": .string("chat_unavailable"),
                "message": .string("Chat is unavailable, try again later"),
                "recoverable": .bool(true)
            ]
        )
        await runtime._debugHandleServerEnvelope(envelope)

        #expect(runtime.isTurnInProgress == false)
        #expect(runtime.lastError == "Chat is unavailable, try again later")
        #expect(runtime.messages.last?.role == .assistant)
        #expect(runtime.messages.last?.text == "Chat is unavailable, try again later")
    }
}

@Suite("Runtime: path monitor reconnect behavior")
struct ResolveKitRuntimePathMonitorTests {
    @Test("Initial satisfied path update does not force reconnect")
    @MainActor
    func initialSatisfiedPathUpdateDoesNotForceReconnect() {
        let runtime = makeRuntime()
        runtime._debugSetConnectionState(.active)

        runtime._debugHandlePathSatisfaction(true)

        #expect(runtime.connectionState == .active)
        runtime.stop()
    }

    @Test("Repeated satisfied path updates keep active connection")
    @MainActor
    func repeatedSatisfiedPathUpdatesKeepConnectionActive() {
        let runtime = makeRuntime()
        runtime._debugSetConnectionState(.active)

        runtime._debugHandlePathSatisfaction(true)
        runtime._debugHandlePathSatisfaction(true)

        #expect(runtime.connectionState == .active)
        runtime.stop()
    }
}

@Suite("Runtime: reconnect trigger diagnostics")
struct ResolveKitRuntimeReconnectDiagnosticsTests {
    @Test("Path transition while active does not force reconnect")
    @MainActor
    func pathTransitionWhileActiveDoesNotForceReconnect() {
        let runtime = makeRuntime()
        runtime._debugSetConnectionState(.active)

        runtime._debugHandlePathSatisfaction(false)
        runtime._debugHandlePathSatisfaction(true)

        #expect(runtime.connectionState == .active)
        #expect(runtime._debugLastReconnectTrigger() == nil)
        runtime.stop()
    }

    @Test("Path transition while failed accelerates reconnect")
    @MainActor
    func pathTransitionWhileFailedAcceleratesReconnect() {
        let runtime = makeRuntime()
        runtime._debugSetConnectionState(.failed)

        runtime._debugHandlePathSatisfaction(true)

        #expect(runtime._debugLastReconnectTrigger() == "path")
        runtime.stop()
    }

    @Test("Transport failure-triggered reconnect is tagged as transport-failure")
    @MainActor
    func transportFailureTriggeredReconnectIsTagged() async {
        let runtime = makeRuntime()
        runtime._debugSetConnectionState(.active)

        await runtime._debugConsumeTransportFailure("synthetic failure")

        #expect(runtime._debugLastReconnectTrigger() == "transport-failure")
        runtime.stop()
    }

    @Test("Transport failure keeps turn in progress for reconnect continuity")
    @MainActor
    func transportFailureKeepsTurnInProgressForReconnectContinuity() async {
        let runtime = makeRuntime()
        runtime._debugSetConnectionState(.active)
        runtime._debugSetTurnInProgress(true)

        await runtime._debugConsumeTransportFailure("synthetic failure")

        #expect(runtime.isTurnInProgress)
        runtime.stop()
    }
}

@Suite("Runtime: tool-result delivery resilience")
struct ResolveKitRuntimeToolResultDeliveryTests {
    @Test("Tool result is queued when WS send fails and flushed via HTTP fallback")
    @MainActor
    func queuesThenFlushesToolResultAfterTransportFailure() async throws {
        let stubSession = makeToolResultStubbedSession()
        ResolveKitToolResultHTTPStub.reset()
        ResolveKitToolResultHTTPStub.setMode(.offline)

        let runtime = makeRuntime(
            sendToolResultsEnabled: true,
            networkSession: stubSession
        )
        try await runtime._debugRegisterFunctions([LightsFunction.self])
        runtime._debugSetTurnInProgress(true)
        runtime._debugSetActiveTurnID("turn-1")
        runtime._debugSetSession(
            ResolveKitSession(
                id: "session-1",
                eventsURL: "/v1/sessions/session-1/events",
                chatCapabilityToken: "chat-capability-token"
            )
        )

        runtime._debugReceiveToolCallRequest(toolRequest(callID: "retry-1", function: "set_lights"))
        await runtime._debugWaitForCoalescingWindow()
        await runtime.approveToolCallBatch()

        let initialByID = Dictionary(uniqueKeysWithValues: runtime.toolCallChecklist.map { ($0.id, $0.status) })
        #expect(initialByID["retry-1"] == .completed)
        #expect(runtime._debugPendingToolResultCallIDs() == ["retry-1"])
        #expect(ResolveKitToolResultHTTPStub.submittedPayloads.map(\.status) == [.success])

        ResolveKitToolResultHTTPStub.setMode(.success)
        await runtime._debugFlushPendingToolResults()

        #expect(runtime._debugPendingToolResultCallIDs().isEmpty)
        #expect(ResolveKitToolResultHTTPStub.submittedPayloads.map(\.status) == [.success, .success])
        #expect(ResolveKitToolResultHTTPStub.submittedPayloads.allSatisfy { $0.callID == "retry-1" })
    }
}

@MainActor
private func makeRuntime(
    sendToolResultsEnabled: Bool = false,
    networkSession: URLSession? = nil
) -> ResolveKitRuntime {
    let config = ResolveKitConfiguration(
        baseURL: URL(string: "http://localhost:8000")!,
        apiKeyProvider: { "test-api-key" },
        llmContextProvider: {
            ["location": .object(["city": .string("Vilnius")])]
        }
    )
    let api = ResolveKitAPIClient(
        baseURL: config.baseURL,
        apiKeyProvider: config.apiKeyProvider,
        session: networkSession
    )
    let eventStream = ResolveKitEventStreamClient(
        apiClient: api,
        session: networkSession ?? .shared
    )
    let registry = ResolveKitRegistry()
    let runtime = ResolveKitRuntime(
        configuration: config,
        apiClient: api,
        eventStreamClient: eventStream,
        registry: registry,
        sendToolResultsEnabled: sendToolResultsEnabled
    )
    return runtime
}

private func makeToolResultStubbedSession() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [ResolveKitToolResultHTTPStub.self]
    return URLSession(configuration: configuration)
}

private final class ResolveKitToolResultHTTPStub: URLProtocol, @unchecked Sendable {
    enum Mode: Sendable {
        case offline
        case success
    }

    private static let lock = NSLock()
    private static var mode: Mode = .offline
    private(set) static var submittedPayloads: [ResolveKitToolResultPayload] = []

    static func setMode(_ newMode: Mode) {
        lock.lock()
        mode = newMode
        lock.unlock()
    }

    static func reset() {
        lock.lock()
        mode = .offline
        submittedPayloads = []
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.path.hasSuffix("/tool-results") == true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.lock.lock()
        let activeMode = Self.mode
        let data = requestBodyData(request)
        if let payload = try? JSONDecoder().decode(ResolveKitToolResultPayload.self, from: data) {
            Self.submittedPayloads.append(payload)
        }
        Self.lock.unlock()

        switch activeMode {
        case .offline:
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
        case .success:
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(#"{"status":"ok"}"#.utf8))
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {}

    private func requestBodyData(_ request: URLRequest) -> Data {
        if let body = request.httpBody {
            return body
        }
        guard let stream = request.httpBodyStream else {
            return Data()
        }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: bufferSize)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }
}

@Suite("Configuration: llm context provider")
struct ResolveKitConfigurationLLMContextTests {
    @Test("Configuration defaults to production agent URL")
    func configurationDefaultsToProductionAgentURL() {
        #expect(ResolveKitDefaults.baseURL.absoluteString == "https://agent.resolvekit.app")

        let config = ResolveKitConfiguration(apiKeyProvider: { "key" })
        #expect(config.baseURL.absoluteString == "https://agent.resolvekit.app")
    }

    @Test("Configuration keeps explicit custom base URL")
    func configurationKeepsExplicitCustomBaseURL() {
        let customURL = URL(string: "http://localhost:8000")!
        let config = ResolveKitConfiguration(
            baseURL: customURL,
            apiKeyProvider: { "key" }
        )

        #expect(config.baseURL == customURL)
    }

    @Test("LLM context provider returns custom JSON context")
    func llmContextProviderReturnsConfiguredContext() {
        let config = ResolveKitConfiguration(
            apiKeyProvider: { "key" },
            llmContextProvider: {
                [
                    "location": .object(["city": .string("Vilnius")]),
                    "network_type": .string("wifi")
                ]
            }
        )

        let value = config.llmContextProvider()
        #expect(value["network_type"] == JSONValue.string("wifi"))
        #expect(value["location"] == JSONValue.object(["city": JSONValue.string("Vilnius")]))
    }

    @Test("Preferred locales fall back to system languages when provider is omitted")
    func preferredLocalesFallBackToSystemLanguages() {
        let config = ResolveKitConfiguration(apiKeyProvider: { "key" })

        #expect(config.resolvedPreferredLocales(preferredLanguages: ["lt-LT", "en-US"]) == ["lt-LT", "en-US"])
    }

    @Test("Preferred locales use explicit provider when present")
    func preferredLocalesUseExplicitProvider() {
        let config = ResolveKitConfiguration(
            apiKeyProvider: { "key" },
            preferredLocalesProvider: { ["fr-FR", "en-US"] }
        )

        #expect(config.resolvedPreferredLocales(preferredLanguages: ["lt-LT", "en-US"]) == ["fr-FR", "en-US"])
    }

    @Test("SDK builds default client payload internally")
    func sdkBuildsDefaultClientPayloadInternally() {
        let payload = ResolveKitClientInfoProvider.makeClientPayload(
            infoDictionary: [
                "CFBundleShortVersionString": "2.3.4",
                "CFBundleVersion": "99"
            ],
            operatingSystemVersion: OperatingSystemVersion(majorVersion: 18, minorVersion: 2, patchVersion: 1)
        )

        #expect(payload["platform"] == ResolveKitPlatform.current.rawValue)
        #expect(payload["os_name"] == ResolveKitClientInfoProvider.osName)
        #expect(payload["os_version"] == "18.2.1")
        #expect(payload["app_version"] == "2.3.4")
        #expect(payload["app_build"] == "99")
        #expect(payload["sdk_name"] == ResolveKitDefaults.sdkName)
        #expect(payload["sdk_version"] == ResolveKitDefaults.sdkVersion)
    }

    @Test("SDK omits empty app build from internal client payload")
    func sdkOmitsEmptyAppBuildFromInternalClientPayload() {
        let payload = ResolveKitClientInfoProvider.makeClientPayload(
            infoDictionary: [
                "CFBundleShortVersionString": "2.3.4",
                "CFBundleVersion": ""
            ],
            operatingSystemVersion: OperatingSystemVersion(majorVersion: 18, minorVersion: 2, patchVersion: 1)
        )

        #expect(payload["app_version"] == "2.3.4")
        #expect(payload["app_build"] == nil)
    }

    @Test("Runtime appearance mode updates from setter")
    @MainActor
    func runtimeAppearanceModeUpdatesFromSetter() {
        let runtime = makeRuntime()
        runtime.setAppearance(.dark)
        #expect(runtime.appearanceMode == .dark)
        runtime.setAppearance(.system)
        #expect(runtime.appearanceMode == .system)
    }
}

@Suite("UI: hosting controller wrappers")
struct ResolveKitUIHostingControllerTests {
    @Test("Hosting controller keeps caller-owned runtime")
    @MainActor
    func hostingControllerKeepsCallerOwnedRuntime() {
        let runtime = makeRuntime()
        let controller = ResolveKitChatViewController(runtime: runtime)

        #expect(controller.runtime === runtime)
        #expect(controller.title == "Support Chat")
    }

    @Test("Hosting controller convenience init creates runtime")
    @MainActor
    func hostingControllerConvenienceInitCreatesRuntime() {
        let controller = ResolveKitChatViewController(configuration: ResolveKitConfiguration(apiKeyProvider: { "key" }))

        #expect(controller.runtime.chatTitle == "Support Chat")
        #expect(controller.title == "Support Chat")
    }

    @Test("Hosting controller title follows runtime chat title")
    @MainActor
    func hostingControllerTitleFollowsRuntimeChatTitle() async {
        let runtime = makeRuntime()
        let controller = ResolveKitChatViewController(runtime: runtime)

        runtime._debugSetChatTitle("Concierge")
        await Task.yield()

        #expect(controller.title == "Concierge")
    }

    #if os(iOS)
    @Test("Hosting controller uses UIKit superclass")
    @MainActor
    func hostingControllerUsesUIKitSuperclass() {
        let controller = ResolveKitChatViewController(runtime: makeRuntime())
        let base: UIHostingController<ResolveKitChatView> = controller
        #expect(base === controller)
    }
    #elseif os(macOS)
    @Test("Hosting controller uses AppKit superclass")
    @MainActor
    func hostingControllerUsesAppKitSuperclass() {
        let controller = ResolveKitChatViewController(runtime: makeRuntime())
        let base: NSHostingController<ResolveKitChatView> = controller
        #expect(base === controller)
    }
    #endif
}

@Suite("Locale resolver")
struct ResolveKitLocaleResolverTests {
    @Test("Resolves explicit locale aliases")
    func resolvesAliases() {
        #expect(ResolveKitLocaleResolver.resolve(locale: "zh-Hans", preferredLocales: []) == "zh-cn")
    }

    @Test("Falls back to preferred locale and english")
    func resolvesPreferredOrEnglish() {
        #expect(ResolveKitLocaleResolver.resolve(locale: nil, preferredLocales: ["fr-FR", "en-US"]) == "fr")
        #expect(ResolveKitLocaleResolver.resolve(locale: nil, preferredLocales: ["xx-YY"]) == "en")
    }
}

private func toolRequest(callID: String, function: String) -> ResolveKitToolCallRequest {
    ResolveKitToolCallRequest(
        callID: callID,
        functionName: function,
        arguments: [
            "room": .string("living room"),
            "on": .bool(true)
        ],
        timeoutSeconds: 5,
        humanDescription: "Run \(function)"
    )
}

// MARK: - Sample functions used in integration tests

struct LightsOutput: Codable {
    let brightness: Int
    let message: String
}

struct LightsFunction: AnyResolveKitFunction {
    static let resolveKitName = "set_lights"
    static let resolveKitDescription = "Turn lights on or off"
    static let resolveKitTimeoutSeconds: Int? = 30
    static let resolveKitParametersSchema: JSONObject = [
        "type": .string("object"),
        "properties": .object([
            "room": .object(["type": .string("string")]),
            "on": .object(["type": .string("boolean")])
        ]),
        "required": .array([.string("room"), .string("on")])
    ]

    static func invoke(arguments: JSONObject, context: ResolveKitFunctionContext) async throws -> JSONValue {
        let room = TypeResolver.coerceString(arguments["room"] ?? .null) ?? ""
        let on = TypeResolver.coerceBool(arguments["on"] ?? .null) ?? false
        let brightness = on ? 100 : 0
        let output = LightsOutput(brightness: brightness, message: "Set \(room) lights to \(brightness)%")
        let data = try JSONEncoder().encode(output)
        return try JSONDecoder().decode(JSONValue.self, from: data)
    }
}

struct WeatherOutput: Codable {
    let city: String
    let condition: String
    let celsius: Int
}

struct WeatherFunction: AnyResolveKitFunction {
    static let resolveKitName = "get_weather"
    static let resolveKitDescription = "Get current weather for a city"
    static let resolveKitTimeoutSeconds: Int? = 10
    static let resolveKitParametersSchema: JSONObject = [
        "type": .string("object"),
        "properties": .object([
            "city": .object(["type": .string("string")])
        ]),
        "required": .array([.string("city")])
    ]

    static func invoke(arguments: JSONObject, context: ResolveKitFunctionContext) async throws -> JSONValue {
        let city = TypeResolver.coerceString(arguments["city"] ?? .null) ?? ""
        let output = WeatherOutput(city: city, condition: "sunny", celsius: 22)
        let data = try JSONEncoder().encode(output)
        return try JSONDecoder().decode(JSONValue.self, from: data)
    }
}

struct SlowFunction: AnyResolveKitFunction {
    static let resolveKitName = "slow_function"
    static let resolveKitDescription = "Sleeps longer than timeout"
    static let resolveKitTimeoutSeconds: Int? = 30
    static let resolveKitParametersSchema: JSONObject = [
        "type": .string("object"),
        "properties": .object([:]),
        "required": .array([])
    ]

    static func invoke(arguments: JSONObject, context: ResolveKitFunctionContext) async throws -> JSONValue {
        try await Task.sleep(nanoseconds: 3_000_000_000)
        return .string("done")
    }
}
