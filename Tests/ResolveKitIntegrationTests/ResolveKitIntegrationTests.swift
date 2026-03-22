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

    @Test("Event stream client uses long-lived session timeouts")
    func eventStreamClientUsesLongLivedSessionTimeouts() {
        let client = ResolveKitAPIClient(
            baseURL: URL(string: "http://localhost:8000")!,
            apiKeyProvider: { "iaa_test_key" }
        )
        let eventStream = ResolveKitEventStreamClient(apiClient: client)
        let configuration = eventStream._debugSessionConfiguration()

        #expect(configuration.timeoutIntervalForRequest >= 60 * 60)
        #expect(configuration.timeoutIntervalForResource >= 60 * 60)
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

    @Test("chat unavailable frame shows transient assistant error bubble")
    @MainActor
    func chatUnavailableFrameShowsTransientAssistantFallback() async throws {
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
        let presentationError = try #require(runtime._debugChatPresentationError())
        #expect(presentationError.message == "We couldn’t reach chat right now.")
        #expect(runtime.messages.isEmpty)
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

    @Test("Repeated satisfied path updates trigger proactive reconnect")
    @MainActor
    func repeatedSatisfiedPathUpdatesTriggerProactiveReconnect() {
        let runtime = makeRuntime()
        runtime._debugSetConnectionState(.active)

        runtime._debugHandlePathSatisfaction(true)
        runtime._debugHandlePathSatisfaction(true)

        #expect(runtime.connectionState == .reconnecting)
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

    @Test("Transport failure ends the active turn and shows transient error state")
    @MainActor
    func transportFailureEndsActiveTurnAndShowsTransientErrorState() async throws {
        let runtime = makeRuntime()
        runtime._debugSetConnectionState(.active)
        runtime._debugSetTurnInProgress(true)

        await runtime._debugConsumeTransportFailure("synthetic failure")

        #expect(runtime.isTurnInProgress == false)
        let presentationError = try #require(runtime._debugChatPresentationError())
        #expect(presentationError.category == .generic)
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

@Suite("Runtime: outgoing messages")
struct ResolveKitRuntimeOutgoingMessageTests {
    @Test("Active runtime posts user message to session messages endpoint")
    @MainActor
    func activeRuntimePostsUserMessage() async throws {
        let stubSession = makeMessageStubbedSession()
        ResolveKitMessageHTTPStub.reset()

        let runtime = makeRuntime(networkSession: stubSession)
        runtime._debugSetSession(
            ResolveKitSession(
                id: "session-1",
                eventsURL: "/v1/sessions/session-1/events",
                chatCapabilityToken: "chat-capability-token"
            )
        )
        runtime._debugSetConnectionState(.active)

        await runtime.sendMessage("Hello from UI")

        let request = try #require(ResolveKitMessageHTTPStub.requests.first { $0.payload?.text == "Hello from UI" })
        #expect(request.method == "POST")
        #expect(request.path == "/v1/sessions/session-1/messages")
        #expect(request.authorization == "Bearer test-api-key")
        #expect(request.chatCapabilityToken == "chat-capability-token")
        #expect(request.payload?.requestID.isEmpty == false)
    }

    @Test("Connecting runtime waits briefly and posts once transport becomes active")
    @MainActor
    func connectingRuntimeWaitsForActiveTransportBeforePosting() async throws {
        let stubSession = makeMessageStubbedSession()
        ResolveKitMessageHTTPStub.reset()

        let runtime = makeRuntime(networkSession: stubSession)
        runtime._debugSetSession(
            ResolveKitSession(
                id: "session-1",
                eventsURL: "/v1/sessions/session-1/events",
                chatCapabilityToken: "chat-capability-token"
            )
        )
        runtime._debugSetConnectionState(.connecting)

        Task { @MainActor in
            await ResolveKitCompatibility.sleep(milliseconds: 80)
            runtime._debugSetConnectionState(.active)
        }

        await runtime.sendMessage("Hello after connect")

        let request = try #require(ResolveKitMessageHTTPStub.requests.first { $0.payload?.text == "Hello after connect" })
        #expect(request.path == "/v1/sessions/session-1/messages")
    }

    @Test("Starting a new send clears any transient chat presentation error")
    @MainActor
    func startingNewSendClearsTransientChatPresentationError() async throws {
        let stubSession = makeMessageStubbedSession()
        ResolveKitMessageHTTPStub.reset()

        let runtime = makeRuntime(networkSession: stubSession)
        runtime._debugSetSession(
            ResolveKitSession(
                id: "session-1",
                eventsURL: "/v1/sessions/session-1/events",
                chatCapabilityToken: "chat-capability-token"
            )
        )
        runtime._debugSetConnectionState(.active)
        runtime._debugSetChatPresentationError(.from(rawMessage: "Heartbeat timeout"))

        await runtime.sendMessage("Retry this")

        #expect(runtime._debugChatPresentationError() == nil)
    }
}

@Suite("Runtime: transient chat presentation errors")
struct ResolveKitRuntimePresentationErrorTests {
    @Test("Transport failure replaces active assistant draft with transient timeout bubble")
    @MainActor
    func transportFailureReplacesActiveAssistantDraftWithTransientTimeoutBubble() async throws {
        let runtime = makeRuntime()
        runtime._debugSetConnectionState(.active)
        runtime._debugSetTurnInProgress(true)

        await runtime._debugHandleServerEnvelope(
            ResolveKitEnvelope(
                type: "assistant_text_delta",
                turnID: "turn-1",
                payload: [
                    "delta": .string("Partial"),
                    "accumulated": .string("Partial response")
                ]
            )
        )

        #expect(runtime.messages.count == 1)
        #expect(runtime.messages.first?.text == "Partial response")

        await runtime._debugConsumeTransportFailure("Heartbeat timeout")

        let presentationError = try #require(runtime._debugChatPresentationError())
        #expect(presentationError.category == .timeout)
        #expect(presentationError.message == "This response is taking longer than expected.")
        #expect(runtime.messages.isEmpty)
        #expect(runtime.isTurnInProgress == false)
    }

    @Test("Chat unavailable server error stays transient instead of appending assistant history")
    @MainActor
    func chatUnavailableServerErrorStaysTransientInsteadOfAppendingAssistantHistory() async throws {
        let runtime = makeRuntime()
        runtime._debugSetTurnInProgress(true)

        await runtime._debugHandleServerEnvelope(
            ResolveKitEnvelope(
                type: "error",
                turnID: "turn-1",
                payload: [
                    "code": .string("chat_unavailable"),
                    "message": .string("Chat is unavailable, try again later"),
                    "recoverable": .bool(false)
                ]
            )
        )

        let presentationError = try #require(runtime._debugChatPresentationError())
        #expect(presentationError.message == "We couldn’t reach chat right now.")
        #expect(runtime.messages.isEmpty)
        #expect(runtime.isTurnInProgress == false)
    }
}

@Suite("Runtime: startup")
struct ResolveKitRuntimeStartupTests {
    @Test("Runtime start is idempotent")
    @MainActor
    func runtimeStartIsIdempotent() async throws {
        let stubSession = makeStartupStubbedSession()
        ResolveKitStartupHTTPStub.reset()

        let runtime = makeRuntime(networkSession: stubSession)

        try await runtime.start()
        try await runtime.start()

        #expect(ResolveKitStartupHTTPStub.requestCount(for: "/v1/sdk/chat-theme") == 1)
        #expect(ResolveKitStartupHTTPStub.requestCount(for: "/v1/functions/bulk") == 1)
        #expect(ResolveKitStartupHTTPStub.requestCount(for: "/v1/sessions") == 1)

        runtime.stop()
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

private func makeMessageStubbedSession() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [ResolveKitMessageHTTPStub.self]
    return URLSession(configuration: configuration)
}

private func makeStartupStubbedSession() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [ResolveKitStartupHTTPStub.self]
    configuration.timeoutIntervalForRequest = 5
    configuration.timeoutIntervalForResource = 5
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

private struct ResolveKitCapturedMessageRequest: Sendable {
    let method: String
    let path: String
    let authorization: String?
    let chatCapabilityToken: String?
    let payload: ResolveKitMessageRequest?
}

private final class ResolveKitMessageHTTPStub: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private(set) static var requests: [ResolveKitCapturedMessageRequest] = []

    static func reset() {
        lock.lock()
        requests = []
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.path.hasSuffix("/messages") == true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let data = requestBodyData(request)
        let captured = ResolveKitCapturedMessageRequest(
            method: request.httpMethod ?? "",
            path: request.url?.path ?? "",
            authorization: request.value(forHTTPHeaderField: "Authorization"),
            chatCapabilityToken: request.value(forHTTPHeaderField: "X-Resolvekit-Chat-Capability"),
            payload: try? JSONDecoder().decode(ResolveKitMessageRequest.self, from: data)
        )

        Self.lock.lock()
        Self.requests.append(captured)
        Self.lock.unlock()

        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 202,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        let body = Data(#"{"turn_id":"turn-1","request_id":"req-1","status":"accepted"}"#.utf8)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
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

private final class ResolveKitStartupHTTPStub: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private static var requestCounts: [String: Int] = [:]

    static func reset() {
        lock.lock()
        requestCounts = [:]
        lock.unlock()
    }

    static func requestCount(for path: String) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return requestCounts[path, default: 0]
    }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "localhost"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let path = request.url?.path ?? ""
        Self.lock.lock()
        Self.requestCounts[path, default: 0] += 1
        Self.lock.unlock()

        let response: HTTPURLResponse
        let body: Data

        switch (request.httpMethod ?? "GET", path) {
        case ("GET", "/v1/sdk/compat"):
            response = HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: [:])!
            body = Data()
        case ("GET", "/v1/sdk/chat-theme"):
            response = HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: [:])!
            body = Data()
        case ("PUT", "/v1/functions/bulk"):
            response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            body = Data("[]".utf8)
        case ("POST", "/v1/sessions"):
            response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            body = Data(
                """
                {
                  "id": "session-1",
                  "events_url": "/v1/sessions/session-1/events",
                  "chat_capability_token": "chat-capability-token",
                  "chat_title": "Support Chat",
                  "message_placeholder": "Message",
                  "initial_message": ""
                }
                """.utf8
            )
        case ("GET", "/v1/sessions/session-1/events"):
            response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "text/event-stream"]
            )!
            body = Data()
        default:
            response = HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!
            body = Data("Unhandled stub request: \(request.httpMethod ?? "") \(path)".utf8)
        }

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if !body.isEmpty {
            client?.urlProtocol(self, didLoad: body)
        }

        if path != "/v1/sessions/session-1/events" {
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {}
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
    @Test("Composer focus dismissal helper only changes state when focused")
    func composerFocusDismissalHelperOnlyChangesStateWhenFocused() {
        var state = ResolveKitChatComposerFocusState()

        #expect(state.dismiss() == false)

        state.isFocused = true

        #expect(state.dismiss() == true)
        #expect(state.isFocused == false)
        #expect(state.dismiss() == false)
    }

    @Test("Initial presentation phase reveals content once and then enables live auto-scroll")
    func initialPresentationPhaseRevealsContentThenEnablesLiveAutoScroll() {
        var phase = ResolveKitChatInitialPresentationPhase.waitingForInitialFetch

        #expect(phase.showsChatContent == false)
        #expect(phase.allowsLiveAutoScroll == false)
        #expect(phase.revealInitialContent() == true)
        #expect(phase.showsChatContent == true)
        #expect(phase.allowsLiveAutoScroll == false)
        #expect(phase.finishInitialScroll() == true)
        #expect(phase.allowsLiveAutoScroll == true)
        #expect(phase.revealInitialContent() == false)
    }

    @Test("Composer focus state does not request re-anchor on focus changes")
    func composerFocusStateDoesNotRequestReanchorOnFocusChanges() {
        var state = ResolveKitChatComposerFocusState()

        #expect(state.updateFocus(false) == false)
        #expect(state.updateFocus(true) == false)
        #expect(state.updateFocus(true) == false)
        #expect(state.updateFocus(false) == false)
        #expect(state.updateFocus(false) == false)
    }

    @Test("Chat uses interactive keyboard dismissal behavior")
    func chatUsesInteractiveKeyboardDismissalBehavior() {
        #expect(ResolveKitScrollKeyboardDismissBehavior.current == .interactive)
    }

    @Test("Composer drag dismissal only reacts to downward drags")
    func composerDragDismissalOnlyReactsToDownwardDrags() {
        #expect(ResolveKitComposerGestureDismissal.shouldDismissKeyboard(translation: CGSize(width: 0, height: 18)))
        #expect(ResolveKitComposerGestureDismissal.shouldDismissKeyboard(translation: CGSize(width: 6, height: 24)))
        #expect(ResolveKitComposerGestureDismissal.shouldDismissKeyboard(translation: CGSize(width: 24, height: 18)) == false)
        #expect(ResolveKitComposerGestureDismissal.shouldDismissKeyboard(translation: CGSize(width: 0, height: 17)) == false)
        #expect(ResolveKitComposerGestureDismissal.shouldDismissKeyboard(translation: CGSize(width: 0, height: -30)) == false)
    }

    @Test("Composer drag focus only reacts to upward drags")
    func composerDragFocusOnlyReactsToUpwardDrags() {
        #expect(ResolveKitComposerGestureDismissal.shouldFocusKeyboard(translation: CGSize(width: 0, height: -18)))
        #expect(ResolveKitComposerGestureDismissal.shouldFocusKeyboard(translation: CGSize(width: 6, height: -24)))
        #expect(ResolveKitComposerGestureDismissal.shouldFocusKeyboard(translation: CGSize(width: 24, height: -18)) == false)
        #expect(ResolveKitComposerGestureDismissal.shouldFocusKeyboard(translation: CGSize(width: 0, height: -17)) == false)
        #expect(ResolveKitComposerGestureDismissal.shouldFocusKeyboard(translation: CGSize(width: 0, height: 30)) == false)
    }

    @Test("Initial composer focus only triggers for a single fetched message")
    func initialComposerFocusOnlyTriggersForSingleFetchedMessage() {
        #expect(ResolveKitInitialComposerFocusPolicy.shouldFocusComposer(initialMessageCount: 1))
        #expect(ResolveKitInitialComposerFocusPolicy.shouldFocusComposer(initialMessageCount: 0) == false)
        #expect(ResolveKitInitialComposerFocusPolicy.shouldFocusComposer(initialMessageCount: 2) == false)
    }

    @Test("Initial presentation scroll only runs when content exceeds the viewport")
    func initialPresentationScrollOnlyRunsWhenContentExceedsViewport() {
        #expect(ResolveKitInitialPresentationScrollPolicy.requiresInitialScroll(anchorMaxY: 801, viewportHeight: 800))
        #expect(ResolveKitInitialPresentationScrollPolicy.requiresInitialScroll(anchorMaxY: 800, viewportHeight: 800) == false)
        #expect(ResolveKitInitialPresentationScrollPolicy.requiresInitialScroll(anchorMaxY: 640, viewportHeight: 800) == false)
        #expect(ResolveKitInitialPresentationScrollPolicy.requiresInitialScroll(anchorMaxY: .infinity, viewportHeight: 800))
    }

    @Test("Initial fetch loading shows thinking bubble")
    func initialFetchLoadingShowsThinkingBubble() {
        #expect(
            ResolveKitThinkingIndicatorVisibilityPolicy.shouldShowThinkingIndicator(
                initialFetchCompleted: false,
                isTurnInProgress: false,
                toolChecklistCount: 0
            )
        )
    }

    @Test("Thinking indicator schedules delayed show when visibility becomes true")
    func thinkingIndicatorSchedulesDelayedShowWhenVisibilityBecomesTrue() {
        #expect(
            ResolveKitThinkingIndicatorTransitionPolicy.transition(for: true) == .scheduleShow(delayMilliseconds: 500)
        )
    }

    @Test("Thinking indicator does not morph into assistant message during initial fetch")
    func thinkingIndicatorDoesNotMorphIntoAssistantMessageDuringInitialFetch() {
        #expect(
            ResolveKitThinkingIndicatorMorphPolicy.morphTargetAssistantID(
                showThinkingIndicator: true,
                initialFetchCompleted: false,
                lastMessage: ResolveKitChatMessage(role: .assistant, text: "Welcome")
            ) == nil
        )
    }

    @Test("Transient error maps timeout failures into customer-facing recovery copy")
    func transientErrorMapsTimeoutFailuresIntoCustomerFacingRecoveryCopy() {
        let presentationError = ResolveKitChatPresentationError.from(rawMessage: "Heartbeat timeout")

        #expect(presentationError.category == .timeout)
        #expect(presentationError.message == "This response is taking longer than expected.")
        #expect(presentationError.recoverySuggestion == "Reload the chat or try again later.")
        #expect(presentationError.hidesAssistantDraft)
    }

    @Test("Transient error maps offline failures into customer-facing recovery copy")
    func transientErrorMapsOfflineFailuresIntoCustomerFacingRecoveryCopy() {
        let presentationError = ResolveKitChatPresentationError.from(
            rawMessage: "The Internet connection appears to be offline."
        )

        #expect(presentationError.category == .network)
        #expect(presentationError.message == "You’re offline right now.")
        #expect(presentationError.recoverySuggestion == "Reload the chat or try again later.")
        #expect(presentationError.hidesAssistantDraft)
    }

    @Test("Transient error maps unknown failures into generic recovery copy")
    func transientErrorMapsUnknownFailuresIntoGenericRecoveryCopy() {
        let presentationError = ResolveKitChatPresentationError.from(rawMessage: "Socket closed unexpectedly")

        #expect(presentationError.category == .generic)
        #expect(presentationError.message == "We couldn’t reach chat right now.")
        #expect(presentationError.recoverySuggestion == "Reload the chat or try again later.")
        #expect(presentationError.hidesAssistantDraft)
    }

    @Test("Transient error bubble suppresses thinking indicator and morph target")
    func transientErrorBubbleSuppressesThinkingIndicatorAndMorphTarget() {
        let presentationError = ResolveKitChatPresentationError.from(rawMessage: "Heartbeat timeout")
        let assistantMessage = ResolveKitChatMessage(role: .assistant, text: "Partial response")

        #expect(
            ResolveKitThinkingIndicatorVisibilityPolicy.shouldShowThinkingIndicator(
                initialFetchCompleted: true,
                isTurnInProgress: true,
                toolChecklistCount: 0,
                presentationError: presentationError
            ) == false
        )
        #expect(
            ResolveKitThinkingIndicatorMorphPolicy.morphTargetAssistantID(
                showThinkingIndicator: true,
                initialFetchCompleted: true,
                lastMessage: assistantMessage,
                presentationError: presentationError
            ) == nil
        )
    }

    @Test("Composer dock keeps a small fixed bottom inset")
    func composerDockKeepsSmallFixedBottomInset() {
        #expect(ResolveKitChatComposerLayout.dockBottomInset() == 4)
    }

    @Test("Timeline reserve uses measured composer height plus breathing room")
    func timelineReserveUsesMeasuredComposerHeightPlusBreathingRoom() {
        #expect(ResolveKitChatComposerLayout.timelineBottomReserve(forComposerHeight: 0) == 12)
        #expect(ResolveKitChatComposerLayout.timelineBottomReserve(forComposerHeight: 52) == 64)
    }

    @Test("Initial presentation scroll stays animated while settling")
    func initialPresentationScrollStaysAnimatedWhileSettling() {
        let plan = ResolveKitChatInitialScrollPlan.initialPresentation
        #expect(plan.steps.count == 2)
        #expect(plan.steps.first?.delayMilliseconds == 200)
        #expect(plan.steps.first?.animated == true)
        #expect(plan.steps.last?.delayMilliseconds == 420)
        #expect(plan.steps.last?.animated == true)
    }

    @Test("Message update scroll stays fully animated while settling to bottom")
    func messageUpdateScrollStaysFullyAnimatedWhileSettling() {
        let plan = ResolveKitChatInitialScrollPlan.messageUpdate
        #expect(plan.steps.count == 2)
        #expect(plan.steps.first?.delayMilliseconds == 20)
        #expect(plan.steps.first?.animated == true)
        #expect(plan.steps.last?.delayMilliseconds == 140)
        #expect(plan.steps.last?.animated == true)
    }

    @Test("Keyboard dismiss scroll starts immediately and stays animated")
    func keyboardDismissScrollStartsImmediatelyAndStaysAnimated() {
        let plan = ResolveKitChatInitialScrollPlan.keyboardDismiss
        #expect(plan.steps.count == 2)
        #expect(plan.steps.first?.delayMilliseconds == 0)
        #expect(plan.steps.first?.animated == true)
        #expect(plan.steps.last?.delayMilliseconds == 120)
        #expect(plan.steps.last?.animated == true)
    }

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
    @Test("Hosting controller keeps navigation item title in sync")
    @MainActor
    func hostingControllerKeepsNavigationItemTitleInSync() async {
        let runtime = makeRuntime()
        let controller = ResolveKitChatViewController(runtime: runtime)

        #expect(controller.navigationItem.title == "Support Chat")

        runtime._debugSetChatTitle("Concierge")
        await Task.yield()

        #expect(controller.navigationItem.title == "Concierge")
    }

    @Test("Hosting controller uses UIKit superclass")
    @MainActor
    func hostingControllerUsesUIKitSuperclass() {
        let controller = ResolveKitChatViewController(runtime: makeRuntime())
        let base: UIHostingController<ResolveKitChatView> = controller
        #expect(base === controller)
    }

    @Test("Hosting controller installs native reload navigation item")
    @MainActor
    func hostingControllerInstallsNativeReloadNavigationItem() {
        let controller = ResolveKitChatViewController(runtime: makeRuntime())

        #expect(controller.navigationItem.rightBarButtonItem != nil)
        #expect(controller.navigationItem.rightBarButtonItem?.action == nil)
        #expect(controller.navigationItem.rightBarButtonItem?.primaryAction != nil)
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
