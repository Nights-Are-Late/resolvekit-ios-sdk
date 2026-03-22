import Combine
import Foundation
import Network
import ResolveKitCore
import ResolveKitNetworking

private enum ResolveKitRuntimeLogger {
    static func log(_ message: String) {
        print("[ResolveKit][Runtime] \(message)")
    }
}

private enum ResolveKitRuntimeError: LocalizedError {
    case duplicateFunctionName(String)
    case unsupportedSDK(String)

    var errorDescription: String? {
        switch self {
        case .duplicateFunctionName(let name):
            return "Duplicate function name across sources: \(name)"
        case .unsupportedSDK(let reason):
            return reason
        }
    }
}

private enum ReconnectTrigger: String {
    case path = "path"
    case transportFailure = "transport-failure"
}

private enum ResolveKitRuntimeDeviceIDStore {
    static func resolveDeviceID(configuration: ResolveKitConfiguration) -> String {
        if let provided = normalizedDeviceID(configuration.deviceIDProvider()) {
            return provided
        }

        let key = storageKey(baseURL: configuration.baseURL)
        if let existing = normalizedDeviceID(UserDefaults.standard.string(forKey: key)) {
            return existing
        }

        let generated = UUID().uuidString.lowercased()
        UserDefaults.standard.set(generated, forKey: key)
        return generated
    }

    private static func normalizedDeviceID(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func storageKey(baseURL: URL) -> String {
        let host = baseURL.host ?? "unknown-host"
        let port = baseURL.port.map(String.init) ?? "default-port"
        let path = baseURL.path.isEmpty ? "/" : baseURL.path
        return "resolvekit.runtime.device_id.\(host):\(port)\(path)"
    }
}

private struct ResolvedFunctionSource {
    let type: any AnyResolveKitFunction.Type
    let source: String
    let packName: String?
    let availability: ResolveKitAvailability?
}

private struct SessionContextSnapshot: Equatable {
    let client: [String: String]
    let llmContext: JSONObject
    let availableFunctionNames: [String]
    let locale: String?
}

public enum ResolveKitToolCallBatchState: String, Sendable {
    case idle
    case awaitingApproval
    case approved
    case declined
    case executing
    case finished
}

public enum ResolveKitToolCallItemStatus: Equatable, Sendable {
    case pendingApproval
    case running
    case completed
    case cancelled(reason: String?)
    case failed(error: String)
}

public struct ToolCallChecklistItem: Identifiable, Equatable, Sendable {
    public let id: String
    public let functionName: String
    public let humanDescription: String
    public let status: ResolveKitToolCallItemStatus
    public let createdAt: Date

    public init(
        id: String,
        functionName: String,
        humanDescription: String,
        status: ResolveKitToolCallItemStatus,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.functionName = functionName
        self.humanDescription = humanDescription
        self.status = status
        self.createdAt = createdAt
    }
}

public struct ToolCallChecklistBatch: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let items: [ToolCallChecklistItem]
    public let state: ResolveKitToolCallBatchState
    public let createdAt: Date
}

public struct ResolveKitChatPresentationError: Equatable, Sendable {
    public enum Category: Equatable, Sendable {
        case network
        case timeout
        case generic
    }

    public let category: Category
    public let message: String
    public let recoverySuggestion: String
    public let hidesAssistantDraft: Bool

    public init(
        category: Category,
        message: String,
        recoverySuggestion: String = "Reload the chat or try again later.",
        hidesAssistantDraft: Bool = true
    ) {
        self.category = category
        self.message = message
        self.recoverySuggestion = recoverySuggestion
        self.hidesAssistantDraft = hidesAssistantDraft
    }

    static func from(rawMessage: String) -> ResolveKitChatPresentationError {
        let normalized = rawMessage.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if normalized.contains("offline")
            || normalized.contains("not connected")
            || normalized.contains("network unavailable")
            || normalized.contains("internet connection") {
            return ResolveKitChatPresentationError(
                category: .network,
                message: "You’re offline right now."
            )
        }

        if normalized.contains("timeout")
            || normalized.contains("timed out")
            || normalized.contains("deadline exceeded") {
            return ResolveKitChatPresentationError(
                category: .timeout,
                message: "This response is taking longer than expected."
            )
        }

        return ResolveKitChatPresentationError(
            category: .generic,
            message: "We couldn’t reach chat right now."
        )
    }

    static func from(error: Error) -> ResolveKitChatPresentationError {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .internationalRoamingOff:
                return ResolveKitChatPresentationError(category: .network, message: "You’re offline right now.")
            case .timedOut:
                return ResolveKitChatPresentationError(
                    category: .timeout,
                    message: "This response is taking longer than expected."
                )
            default:
                break
            }
        }

        return from(rawMessage: error.localizedDescription)
    }
}

@MainActor
public final class ResolveKitRuntime: ObservableObject {
    @Published public private(set) var messages: [ResolveKitChatMessage] = []
    @Published public private(set) var connectionState: ResolveKitConnectionState = .idle
    @Published public private(set) var isTurnInProgress: Bool = false
    @Published public private(set) var pendingToolCall: ResolveKitPendingToolCall?
    @Published public private(set) var toolCallChecklist: [ToolCallChecklistItem] = []
    @Published public private(set) var toolCallBatchState: ResolveKitToolCallBatchState = .idle
    @Published public private(set) var toolCallBatches: [ToolCallChecklistBatch] = []
    @Published public private(set) var executionLog: [String] = []
    @Published public private(set) var lastError: String?
    @Published public private(set) var chatPresentationError: ResolveKitChatPresentationError?
    @Published public private(set) var chatTheme: ResolveKitChatTheme = .default
    @Published public private(set) var appearanceMode: ResolveKitAppearanceMode = .system
    @Published public private(set) var currentLocale: String = "en"
    @Published public private(set) var chatTitle: String = "Support Chat"
    @Published public private(set) var messagePlaceholder: String = "Message"
    @Published public private(set) var initialFetchCompleted = false

    private let configuration: ResolveKitConfiguration
    private let apiClient: ResolveKitAPIClient
    private let eventStreamClient: ResolveKitEventStreamClient
    private let registry: ResolveKitRegistry
    private let sendToolResultsEnabled: Bool

    private var session: ResolveKitSession?
    private var lastSyncedSessionContext: SessionContextSnapshot?
    private var didReuseActiveSession = false
    private var isReloadingWithNewSession = false
    private var startTask: Task<Void, Error>?
    private var eventStreamTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var reconnectAttempt: Int = 0
    private static let maxReconnectDelay: Double = 30
    private var lastReconnectTrigger: ReconnectTrigger?
    private var lastReceivedEventID: String? {
        didSet {
            guard let sessionID = session?.id, let value = lastReceivedEventID else { return }
            UserDefaults.standard.set(value, forKey: "rk_cursor_\(sessionID)")
        }
    }
    private var activeTurnID: String?

    private var pathMonitor: NWPathMonitor?
    private let pathMonitorQueue = DispatchQueue(label: "com.resolvekit.pathmonitor", qos: .utility)
    private var pathMonitorDebounceTask: Task<Void, Never>?
    private var lastStablePathSatisfied: Bool?

    private var consecutiveAuthFailures: Int = 0
    private static let maxConsecutiveAuthFailures = 3
    private static let sendReadyWaitTimeoutMilliseconds: UInt64 = 4_000
    private static let sendReadyPollIntervalMilliseconds: UInt64 = 100
    private var activeAssistantDraft = ""
    private var activeAssistantMessageID: UUID?

    private let toolBatchCoalescingDelayMilliseconds: UInt64 = 250
    private var collectingToolCalls: [ResolveKitToolCallRequest] = []
    private var collectionTask: Task<Void, Never>?
    private var queuedBatches: [[ResolveKitToolCallRequest]] = []
    private var activeBatchRequests: [ResolveKitToolCallRequest] = []
    private var activeBatchID: UUID?
    private var pendingToolResults: [ResolveKitToolResultPayload] = []
    private var isFlushingPendingToolResults = false
    private var processedToolCallIDs: Set<String> = []
    private var processedEventIDs: Set<String> = []
    private var lastSSEDataReceivedAt: Date?
    private var heartbeatWatchdogTask: Task<Void, Never>?
    private static let heartbeatStaleThresholdSeconds: TimeInterval = 25
    private let unavailableMessage = "Chat is unavailable, try again later"

    public init(configuration: ResolveKitConfiguration) {
        self.configuration = configuration
        let apiClient = ResolveKitAPIClient(baseURL: configuration.baseURL, apiKeyProvider: configuration.apiKeyProvider)
        self.apiClient = apiClient
        self.eventStreamClient = ResolveKitEventStreamClient(apiClient: apiClient)
        self.registry = ResolveKitRegistry()
        self.sendToolResultsEnabled = true
        self.currentLocale = ResolveKitLocaleResolver.resolve(
            locale: configuration.localeProvider(),
            preferredLocales: configuration.resolvedPreferredLocales()
        )
    }

    init(
        configuration: ResolveKitConfiguration,
        apiClient: ResolveKitAPIClient,
        eventStreamClient: ResolveKitEventStreamClient,
        registry: ResolveKitRegistry,
        sendToolResultsEnabled: Bool
    ) {
        self.configuration = configuration
        self.apiClient = apiClient
        self.eventStreamClient = eventStreamClient
        self.registry = registry
        self.sendToolResultsEnabled = sendToolResultsEnabled
        self.currentLocale = ResolveKitLocaleResolver.resolve(
            locale: configuration.localeProvider(),
            preferredLocales: configuration.resolvedPreferredLocales()
        )
    }

    public func start() async throws {
        if let startTask {
            try await startTask.value
            return
        }

        // SwiftUI view reappearance can trigger `.task` again. Once a session exists,
        // let the existing connection/reconnect machinery continue instead of re-running startup.
        guard session == nil else {
            startPathMonitor()
            return
        }

        let task = Task { @MainActor in
            startPathMonitor()
            try await startInternal(reuseActiveSession: true)
        }
        startTask = task

        do {
            try await task.value
            startTask = nil
        } catch {
            startTask = nil
            throw error
        }
    }

    public func stop() {
        startTask?.cancel()
        startTask = nil
        stopPathMonitor()
        stopHeartbeatWatchdog()
        reconnectTask?.cancel()
        reconnectTask = nil
        reconnectAttempt = 0
        consecutiveAuthFailures = 0
        eventStreamTask?.cancel()
        eventStreamTask = nil
        pendingToolResults = []
        lastStablePathSatisfied = nil
        lastReconnectTrigger = nil
        lastReceivedEventID = nil
        activeTurnID = nil
        processedEventIDs = []
        connectionState = .idle
    }

    public func prepareForReloadWithNewSession() {
        isReloadingWithNewSession = true
        startTask?.cancel()
        startTask = nil
        stopHeartbeatWatchdog()
        reconnectTask?.cancel()
        reconnectTask = nil
        reconnectAttempt = 0
        consecutiveAuthFailures = 0
        eventStreamTask?.cancel()
        eventStreamTask = nil
        session = nil
        pendingToolResults = []
        lastSyncedSessionContext = nil
        lastStablePathSatisfied = nil
        lastReconnectTrigger = nil
        lastReceivedEventID = nil
        activeTurnID = nil
        processedEventIDs = []
        didReuseActiveSession = false
        messages = []
        initialFetchCompleted = false
        activeAssistantDraft = ""
        activeAssistantMessageID = nil
        lastError = nil
        clearChatPresentationError()
        isTurnInProgress = false
        resetToolCallFlowForNewTurn()
    }

    public func reloadWithNewSession() async {
        prepareForReloadWithNewSession()
        defer { isReloadingWithNewSession = false }
        do {
            try await startInternal(reuseActiveSession: false)
        } catch {
            connectionState = .failed
            lastError = error.localizedDescription
        }
    }

    private func scheduleReconnect(trigger: ReconnectTrigger) {
        lastReconnectTrigger = trigger
        ResolveKitRuntimeLogger.log("Reconnect trigger=\(trigger.rawValue)")
        reconnectTask?.cancel()
        let attempt = reconnectAttempt
        reconnectAttempt += 1
        reconnectTask = Task { [weak self] in
            guard let self else { return }
            let delay = min(pow(2.0, Double(attempt)), Self.maxReconnectDelay)
            ResolveKitRuntimeLogger.log("Reconnect in \(Int(delay))s (attempt \(attempt + 1))")
            await ResolveKitCompatibility.sleep(seconds: delay)
            guard !Task.isCancelled else { return }
            guard self.connectionState == .reconnecting || self.connectionState == .failed else { return }
            self.connectionState = .reconnecting
            do {
                try await self.reconnectEventStream()
                } catch {
                    guard !Task.isCancelled else { return }
                    if self.connectionState != .blocked {
                        self.connectionState = .reconnecting
                        self.scheduleReconnect(trigger: trigger)
                    }
                }
        }
    }

    private func reconnectEventStream() async throws {
        guard let key = configuration.apiKeyProvider(), !key.isEmpty else {
            connectionState = .blocked
            lastError = "Missing API key"
            presentChatPresentationError(rawMessage: lastError ?? "Missing API key")
            return
        }
        guard let existingSession = session else {
            // No session established yet — run full init.
            try await startInternal(reuseActiveSession: true)
            return
        }
        do {
            connectionState = .connecting
            try await connectEventStream(eventsPath: existingSession.eventsURL, cursor: lastReceivedEventID)
        } catch ResolveKitAPIClientError.chatUnavailable {
            ResolveKitRuntimeLogger.log("Reconnect blocked by chat_unavailable")
            guard !isReloadingWithNewSession else { return }
            connectionState = .blocked
            presentChatUnavailable()
        } catch ResolveKitAPIClientError.serverError(let statusCode, _) where statusCode == 401 {
            guard !isReloadingWithNewSession else { return }
            consecutiveAuthFailures += 1
            ResolveKitRuntimeLogger.log("Auth failed during reconnect (attempt \(consecutiveAuthFailures)/\(Self.maxConsecutiveAuthFailures))")
            if consecutiveAuthFailures >= Self.maxConsecutiveAuthFailures {
                connectionState = .blocked
                lastError = "Authentication failed. Check your API key."
                presentChatPresentationError(rawMessage: lastError ?? "Authentication failed")
                return
            }
            connectionState = .failed
            lastError = "Authentication failed – retrying"
            presentChatPresentationError(rawMessage: lastError ?? "Authentication failed")
            throw ResolveKitAPIClientError.serverError(statusCode: statusCode, message: "Auth retry")
        } catch ResolveKitAPIClientError.serverError(let statusCode, _) where statusCode == 404 {
            // Session expired on the server — restart fully to get a new session.
            ResolveKitRuntimeLogger.log("Session not found during reconnect (404), re-initialising")
            session = nil
            try await startInternal(reuseActiveSession: true)
        } catch {
            guard !isReloadingWithNewSession else { return }
            connectionState = .failed
            lastError = error.localizedDescription
            presentChatPresentationError(error)
            throw error
        }
    }

    // MARK: - NWPathMonitor

    private func startPathMonitor() {
        guard pathMonitor == nil else { return }
        let monitor = NWPathMonitor()
        pathMonitor = monitor
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            Task { @MainActor in self.handlePathUpdate(path) }
        }
        monitor.start(queue: pathMonitorQueue)
    }

    private func stopPathMonitor() {
        pathMonitorDebounceTask?.cancel()
        pathMonitorDebounceTask = nil
        pathMonitor?.cancel()
        pathMonitor = nil
    }

    private func handlePathUpdate(_ path: NWPath) {
        pathMonitorDebounceTask?.cancel()
        pathMonitorDebounceTask = Task { [weak self] in
            guard let self else { return }
            await ResolveKitCompatibility.sleep(milliseconds: 500)
            guard !Task.isCancelled else { return }
            self.onPathStable(path)
        }
    }

    private func onPathStable(_ path: NWPath) {
        onPathSatisfactionStable(path.status == .satisfied)
    }

    private func onPathSatisfactionStable(_ isSatisfied: Bool) {
        let previousSatisfied = lastStablePathSatisfied
        lastStablePathSatisfied = isSatisfied

        guard connectionState != .blocked,
              connectionState != .idle,
              connectionState != .registering,
              connectionState != .connecting else { return }

        guard isSatisfied else {
            ResolveKitRuntimeLogger.log("Path update: network unavailable, skipping reconnect")
            return
        }

        if connectionState == .active || connectionState == .reconnected {
            guard let previousSatisfied else {
                ResolveKitRuntimeLogger.log("Path update: initial satisfied status observed, keeping active connection")
                return
            }
            if previousSatisfied && isSatisfied {
                ResolveKitRuntimeLogger.log("Path update: network interface transition detected (e.g. WiFi→Cell), proactive reconnect")
                eventStreamTask?.cancel()
                eventStreamTask = nil
                stopHeartbeatWatchdog()
                connectionState = .reconnecting
                reconnectAttempt = 0
                scheduleReconnect(trigger: .path)
                return
            }
            if previousSatisfied {
                ResolveKitRuntimeLogger.log("Path update: network transition detected, keeping active connection")
            }
            return
        }

        if connectionState == .reconnecting || connectionState == .failed {
            ResolveKitRuntimeLogger.log("Path update: network satisfied, accelerating reconnect")
            reconnectAttempt = 0
            reconnectTask?.cancel()
            reconnectTask = nil
            connectionState = .reconnecting
            scheduleReconnect(trigger: .path)
        }
    }

    private func startInternal(reuseActiveSession: Bool) async throws {
        guard let key = configuration.apiKeyProvider(), !key.isEmpty else {
            connectionState = .blocked
            lastError = "Missing API key"
            presentChatPresentationError(rawMessage: lastError ?? "Missing API key")
            initialFetchCompleted = true
            return
        }

        initialFetchCompleted = false

        do {
            try await verifySDKCompatibility()
            await refreshChatTheme()

            let resolvedFunctions = try resolveFunctionSources()

            // Register functions (idempotent — reset first to allow re-start)
            await registry.reset()
            try await registry.register(resolvedFunctions.map(\.type))

            connectionState = .registering
            let definitions = resolvedFunctions.map {
                ResolveKitDefinition(
                    name: $0.type.resolveKitName,
                    description: $0.type.resolveKitDescription,
                    parametersSchema: $0.type.resolveKitParametersSchema,
                    timeoutSeconds: $0.type.resolveKitTimeoutSeconds,
                    availability: $0.availability,
                    source: $0.source,
                    packName: $0.packName
                )
            }
            try await apiClient.bulkSyncFunctions(definitions)

            connectionState = .connecting
            let deviceID = ResolveKitRuntimeDeviceIDStore.resolveDeviceID(configuration: configuration)
            let contextSnapshot = makeSessionContextSnapshot(
                registeredFunctionNames: resolvedFunctions.map { $0.type.resolveKitName }
            )
            let session = try await apiClient.createSession(
                ResolveKitSessionCreateRequest(
                    deviceID: deviceID,
                    client: contextSnapshot.client,
                    llmContext: contextSnapshot.llmContext,
                    availableFunctionNames: contextSnapshot.availableFunctionNames,
                    locale: contextSnapshot.locale,
                    preferredLocales: configuration.resolvedPreferredLocales(),
                    reuseActiveSession: reuseActiveSession
                )
            )
            adoptSession(session)
            clearChatPresentationError()
            lastSyncedSessionContext = contextSnapshot
            currentLocale = ResolveKitLocaleResolver.resolve(
                locale: session.locale,
                preferredLocales: configuration.resolvedPreferredLocales()
            )
            chatTitle = session.chatTitle
            messagePlaceholder = session.messagePlaceholder
            didReuseActiveSession = session.reusedActiveSession
            if session.reusedActiveSession {
                await loadReusedSessionHistory(sessionID: session.id, chatCapabilityToken: session.chatCapabilityToken)
                reconcileInitialMessageAfterReuse(expected: session.initialMessage)
            } else if session.initialMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                messages.append(.init(role: .assistant, text: session.initialMessage))
            }
            initialFetchCompleted = true
            try await connectEventStream(eventsPath: session.eventsURL, cursor: lastReceivedEventID)
        } catch ResolveKitAPIClientError.chatUnavailable {
            ResolveKitRuntimeLogger.log(
                "Session start blocked by chat_unavailable (integration disabled, chat token invalid, or provider unavailable)"
            )
            connectionState = .blocked
            presentChatUnavailable()
            initialFetchCompleted = true
            return
        } catch ResolveKitRuntimeError.unsupportedSDK {
            initialFetchCompleted = true
            return
        } catch ResolveKitAPIClientError.serverError(let statusCode, _) where statusCode == 401 {
            consecutiveAuthFailures += 1
            ResolveKitRuntimeLogger.log("Auth failed (attempt \(consecutiveAuthFailures)/\(Self.maxConsecutiveAuthFailures)) – token may be expired, will retry")
            if consecutiveAuthFailures >= Self.maxConsecutiveAuthFailures {
                ResolveKitRuntimeLogger.log("Auth failed \(Self.maxConsecutiveAuthFailures) times, blocking")
                connectionState = .blocked
                lastError = "Authentication failed. Check your API key."
                presentChatPresentationError(rawMessage: lastError ?? "Authentication failed")
                initialFetchCompleted = true
                return
            }
            connectionState = .failed
            lastError = "Authentication failed – retrying"
            presentChatPresentationError(rawMessage: lastError ?? "Authentication failed")
            initialFetchCompleted = true
            throw ResolveKitAPIClientError.serverError(statusCode: statusCode, message: "Auth retry")
        } catch {
            connectionState = .failed
            lastError = error.localizedDescription
            presentChatPresentationError(error)
            initialFetchCompleted = true
            throw error
        }
    }

    public func setAppearance(_ mode: ResolveKitAppearanceMode) {
        appearanceMode = mode
    }

    public func refreshSessionContext() async throws {
        try await syncSessionContextIfNeeded(force: true)
    }

    public func sendMessage(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            ResolveKitRuntimeLogger.log("sendMessage ignored empty text")
            return
        }
        guard !isTurnInProgress else {
            ResolveKitRuntimeLogger.log("sendMessage blocked because turn already in progress")
            return
        }

        ResolveKitRuntimeLogger.log(
            "sendMessage requested state=\(connectionState.rawValue) session_id=\(session?.id ?? "nil") text_len=\(trimmed.count)"
        )

        messages.append(.init(role: .user, text: trimmed))
        isTurnInProgress = true
        activeAssistantDraft = ""
        activeAssistantMessageID = nil
        clearChatPresentationError()
        resetToolCallFlowForNewTurn()

        do {
            try await syncSessionContextIfNeeded()
        } catch {
            ResolveKitRuntimeLogger.log("Failed to sync session context before send: \(error.localizedDescription)")
        }

        let isReadyToSend = await waitForReadyToSendMessage()
        ResolveKitRuntimeLogger.log(
            "sendMessage readiness state=\(connectionState.rawValue) ready=\(isReadyToSend)"
        )
        guard isReadyToSend else {
            failTurn("Not connected. Current state: \(connectionState.rawValue)")
            return
        }

        let requestID = UUID().uuidString.lowercased()
        let maxAttempts = 3
        var lastError: String?

        for attempt in 0..<maxAttempts {
            if attempt > 0 {
                let delay = min(pow(2.0, Double(attempt - 1)), 4.0)
                await ResolveKitCompatibility.sleep(seconds: delay)
                guard await waitForReadyToSendMessage() else { continue }
            }

            do {
                let accepted = try await apiClient.sendMessage(
                    sessionID: session?.id ?? "",
                    requestBody: ResolveKitMessageRequest(text: trimmed, requestID: requestID, locale: currentLocale),
                    chatCapabilityToken: session?.chatCapabilityToken ?? ""
                )
                activeTurnID = accepted.turnID
                ResolveKitRuntimeLogger.log(
                    "sendMessage accepted turn_id=\(accepted.turnID) request_id=\(accepted.requestID)"
                )
                return
            } catch {
                lastError = error.localizedDescription
                ResolveKitRuntimeLogger.log("sendMessage attempt \(attempt + 1)/\(maxAttempts) failed: \(error.localizedDescription)")
            }
        }

        await awaitTurnConfirmationOrFail(lastError: lastError, maxAttempts: maxAttempts)
    }

    private func waitForReadyToSendMessage() async -> Bool {
        if connectionState == .active || connectionState == .reconnected {
            return true
        }

        let iterations = Int(Self.sendReadyWaitTimeoutMilliseconds / Self.sendReadyPollIntervalMilliseconds)
        for _ in 0..<iterations {
            if connectionState == .active || connectionState == .reconnected {
                return true
            }
            if connectionState == .blocked || connectionState == .idle {
                return false
            }
            await ResolveKitCompatibility.sleep(milliseconds: Self.sendReadyPollIntervalMilliseconds)
        }

        return connectionState == .active || connectionState == .reconnected
    }

    private func resolveFunctionSources() throws -> [ResolvedFunctionSource] {
        var resolved: [ResolvedFunctionSource] = configuration.functions.map {
            ResolvedFunctionSource(type: $0, source: "app_inline", packName: nil, availability: nil)
        }

        let currentPlatform = ResolveKitPlatform.current
        for pack in configuration.functionPacks where pack.supportedPlatforms.contains(currentPlatform) {
            let availability = ResolveKitAvailability(platforms: pack.supportedPlatforms.map(\.rawValue))
            resolved += pack.functions.map {
                ResolvedFunctionSource(
                    type: $0,
                    source: "playbook_pack",
                    packName: pack.packName,
                    availability: availability
                )
            }
        }

        var seen = Set<String>()
        for fn in resolved {
            if seen.contains(fn.type.resolveKitName) {
                throw ResolveKitRuntimeError.duplicateFunctionName(fn.type.resolveKitName)
            }
            seen.insert(fn.type.resolveKitName)
        }
        return resolved
    }

    private func normalizedFunctionNames(_ names: [String]) -> [String] {
        var seen = Set<String>()
        var normalized: [String] = []
        for name in names {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            guard !seen.contains(trimmed) else { continue }
            seen.insert(trimmed)
            normalized.append(trimmed)
        }
        return normalized
    }

    private func resolveAvailableFunctionNames(registeredFunctionNames: [String]) -> [String] {
        let registered = normalizedFunctionNames(registeredFunctionNames)
        guard let provider = configuration.availableFunctionNamesProvider else {
            return registered
        }

        let requested = normalizedFunctionNames(provider())
        guard !requested.isEmpty else {
            return registered
        }

        let registeredSet = Set(registered)
        let filtered = requested.filter { registeredSet.contains($0) }
        return filtered.isEmpty ? registered : filtered
    }

    private func makeSessionContextSnapshot(registeredFunctionNames: [String]) -> SessionContextSnapshot {
        SessionContextSnapshot(
            client: ResolveKitClientInfoProvider.makeClientPayload(),
            llmContext: configuration.llmContextProvider(),
            availableFunctionNames: resolveAvailableFunctionNames(registeredFunctionNames: registeredFunctionNames),
            locale: configuration.localeProvider()
        )
    }

    private func syncSessionContextIfNeeded(force: Bool = false) async throws {
        guard let session else { return }

        let definitions = await registry.definitions
        let snapshot = makeSessionContextSnapshot(registeredFunctionNames: definitions.map(\.name))
        if !force, snapshot == lastSyncedSessionContext {
            return
        }

        let updated = try await apiClient.patchSessionContext(
            sessionID: session.id,
            chatCapabilityToken: session.chatCapabilityToken,
            requestBody: ResolveKitSessionContextPatchRequest(
                client: snapshot.client,
                llmContext: snapshot.llmContext,
                availableFunctionNames: snapshot.availableFunctionNames,
                locale: snapshot.locale
            )
        )

        lastSyncedSessionContext = snapshot
        currentLocale = ResolveKitLocaleResolver.resolve(
            locale: updated.locale,
            preferredLocales: configuration.resolvedPreferredLocales()
        )
    }

    private func verifySDKCompatibility() async throws {
        do {
            let compat = try await apiClient.sdkCompatibility()
            if let error = compatibilityError(compat: compat) {
                connectionState = .blocked
                lastError = error
                throw ResolveKitRuntimeError.unsupportedSDK(error)
            }
        } catch ResolveKitAPIClientError.serverError(let statusCode, _) where statusCode == 404 {
            // Backward-compatible backend: skip compatibility gate.
        }
    }

    private func refreshChatTheme() async {
        do {
            chatTheme = try await apiClient.chatTheme()
        } catch ResolveKitAPIClientError.serverError(let statusCode, _) where statusCode == 404 {
            // Backward-compatible backend: keep defaults.
            chatTheme = .default
        } catch {
            ResolveKitRuntimeLogger.log("Failed to fetch chat theme: \(error.localizedDescription)")
            chatTheme = .default
        }
    }

    private func compatibilityError(compat: ResolveKitSDKCompat) -> String? {
        let localVersion = ResolveKitDefaults.sdkVersion
        guard let localMajor = parseMajor(localVersion) else {
            return "Invalid SDK version format: \(localVersion)"
        }

        if !compat.supportedSDKMajorVersions.contains(localMajor) {
            return "SDK major version \(localMajor) is unsupported by server."
        }

        if compareVersions(localVersion, compat.minimumSDKVersion) < 0 {
            return "SDK \(localVersion) is below minimum required \(compat.minimumSDKVersion)."
        }
        return nil
    }

    private func parseMajor(_ version: String) -> Int? {
        Int(version.split(separator: ".").first ?? "")
    }

    private func compareVersions(_ lhs: String, _ rhs: String) -> Int {
        let l = lhs.split(separator: ".").compactMap { Int($0) }
        let r = rhs.split(separator: ".").compactMap { Int($0) }
        let count = max(l.count, r.count)
        for i in 0..<count {
            let lv = i < l.count ? l[i] : 0
            let rv = i < r.count ? r[i] : 0
            if lv < rv { return -1 }
            if lv > rv { return 1 }
        }
        return 0
    }

    public func approveToolCallBatch() async {
        guard toolCallBatchState == .awaitingApproval else { return }
        guard !activeBatchRequests.isEmpty else { return }

        setToolCallBatchState(.approved)
        setToolCallBatchState(.executing)

        for call in activeBatchRequests {
            updateChecklistStatus(for: [call.callID], to: .running)
            let event = await executeBatchStep(call)
            switch event {
            case .completed(let callID):
                updateChecklistStatus(for: [callID], to: .completed)
                if let name = request(forCallID: callID)?.functionName {
                    executionLog.append("Success: \(name)")
                }
            case .failed(let callID, let error):
                updateChecklistStatus(for: [callID], to: .failed(error: error))
                if let name = request(forCallID: callID)?.functionName {
                    executionLog.append("Error: \(name) - \(error)")
                }
            case .cancelled(let callID, let reason):
                updateChecklistStatus(for: [callID], to: .cancelled(reason: reason))
                if let name = request(forCallID: callID)?.functionName {
                    executionLog.append("Cancelled: \(name)\(reason.map { " - \($0)" } ?? "")")
                }
            }
        }

        pendingToolCall = nil
        setToolCallBatchState(.finished)
        activeBatchID = nil
        activeBatchRequests = []
        presentNextQueuedBatchIfNeeded()
    }

    public func declineToolCallBatch() async {
        guard toolCallBatchState == .awaitingApproval else { return }
        guard !activeBatchRequests.isEmpty else { return }

        setToolCallBatchState(.declined)

        await withTaskGroup(of: BatchExecutionEvent.self) { group in
            for call in activeBatchRequests {
                group.addTask { [weak self] in
                    guard let self else {
                        return BatchExecutionEvent.failed(callID: call.callID, error: "Runtime deallocated")
                    }

                    let payload = ResolveKitToolResultPayload(
                        callID: call.callID,
                        status: .error,
                        result: nil,
                        error: "User denied action"
                    )
                    if self.sendToolResultsEnabled {
                        _ = await self.deliverToolResultReliably(payload)
                    }
                    return BatchExecutionEvent.cancelled(callID: call.callID, reason: "User denied action")
                }
            }

            for await event in group {
                switch event {
                case .cancelled(let callID, let reason):
                    updateChecklistStatus(for: [callID], to: .cancelled(reason: reason))
                    if let name = request(forCallID: callID)?.functionName {
                        executionLog.append("Denied: \(name)\(reason.map { " - \($0)" } ?? "")")
                    }
                case .failed(let callID, let error):
                    updateChecklistStatus(for: [callID], to: .failed(error: error))
                    if let name = request(forCallID: callID)?.functionName {
                        executionLog.append("Error: \(name) - \(error)")
                    }
                case .completed(let callID):
                    updateChecklistStatus(for: [callID], to: .completed)
                }
            }
        }

        pendingToolCall = nil
        setToolCallBatchState(.finished)
        activeBatchID = nil
        activeBatchRequests = []
        presentNextQueuedBatchIfNeeded()
    }

    // Backward-compatible wrappers.
    public func approveCurrentToolCall() async {
        await approveToolCallBatch()
    }

    // Backward-compatible wrappers.
    public func denyCurrentToolCall() async {
        await declineToolCallBatch()
    }

    private nonisolated func recordSSEHeartbeat() {
        Task { @MainActor in
            self.lastSSEDataReceivedAt = Date()
        }
    }

    private func startHeartbeatWatchdog() {
        heartbeatWatchdogTask?.cancel()
        lastSSEDataReceivedAt = Date()
        heartbeatWatchdogTask = Task { [weak self] in
            while !Task.isCancelled {
                await ResolveKitCompatibility.sleep(seconds: 5)
                guard let self, !Task.isCancelled else { return }
                guard let lastData = self.lastSSEDataReceivedAt else { continue }
                let staleness = Date().timeIntervalSince(lastData)
                if staleness > Self.heartbeatStaleThresholdSeconds {
                    ResolveKitRuntimeLogger.log("SSE heartbeat stale (\(Int(staleness))s), forcing reconnect")
                    self.eventStreamTask?.cancel()
                    self.stopHeartbeatWatchdog()
                    await self.handleTransportFailure("Heartbeat timeout")
                    return
                }
            }
        }
    }

    private func stopHeartbeatWatchdog() {
        heartbeatWatchdogTask?.cancel()
        heartbeatWatchdogTask = nil
        lastSSEDataReceivedAt = nil
    }

    private func connectEventStream(eventsPath: String, cursor: String?) async throws {
        eventStreamTask?.cancel()
        eventStreamTask = nil
        let stream = try await eventStreamClient.stream(
            eventsPath: eventsPath,
            chatCapabilityToken: session?.chatCapabilityToken ?? "",
            cursor: cursor,
            onHeartbeat: { [weak self] in self?.recordSSEHeartbeat() }
        )
        let isReconnectWithTurnInProgress = session != nil && isTurnInProgress
        connectionState = didReuseActiveSession || cursor != nil ? .reconnected : .active
        clearChatPresentationError()
        reconnectAttempt = 0
        consecutiveAuthFailures = 0
        startHeartbeatWatchdog()
        _ = await flushPendingToolResults(reason: "event stream connected")
        if isReconnectWithTurnInProgress {
            Task { await self.reconcileInProgressTurnAfterReconnect() }
        }
        eventStreamTask = Task { [weak self] in
            guard let self else { return }
            do {
                for try await event in stream {
                    if let eventID = event.id {
                        guard !self.processedEventIDs.contains(eventID) else {
                            self.lastReceivedEventID = eventID
                            continue
                        }
                        self.processedEventIDs.insert(eventID)
                        self.lastReceivedEventID = eventID
                    }
                    await self.handleServerEnvelope(event.envelope)
                }
                await self.handleTransportFailure("Event stream closed")
            } catch {
                await self.handleTransportFailure(error.localizedDescription)
            }
        }
    }

    private func handleTransportFailure(_ message: String) async {
        if isReloadingWithNewSession {
            ResolveKitRuntimeLogger.log("Suppressing transport failure during reload: \(message)")
            return
        }
        stopHeartbeatWatchdog()
        if lastError == unavailableMessage {
            connectionState = .blocked
            return
        }
        connectionState = .failed
        lastError = message
        isTurnInProgress = false
        activeTurnID = nil
        presentChatPresentationError(rawMessage: message)
        if connectionState == .failed {
            scheduleReconnect(trigger: .transportFailure)
        }
    }

    private func presentChatPresentationError(_ error: ResolveKitChatPresentationError) {
        if error.hidesAssistantDraft {
            discardActiveAssistantDraft()
        }
        chatPresentationError = error
    }

    private func presentChatPresentationError(rawMessage: String) {
        presentChatPresentationError(.from(rawMessage: rawMessage))
    }

    private func presentChatPresentationError(_ error: Error) {
        presentChatPresentationError(.from(error: error))
    }

    private func clearChatPresentationError() {
        chatPresentationError = nil
    }

    private func discardActiveAssistantDraft() {
        guard let activeAssistantMessageID else {
            activeAssistantDraft = ""
            return
        }
        messages.removeAll { $0.id == activeAssistantMessageID }
        self.activeAssistantMessageID = nil
        activeAssistantDraft = ""
    }

    private func handleServerEnvelope(_ envelope: ResolveKitEnvelope) async {
        if isReloadingWithNewSession {
            ResolveKitRuntimeLogger.log("Suppressing server envelope during reload: \(envelope.type)")
            return
        }
        if isTurnInProgress, activeTurnID == nil, let turnID = envelope.turnID {
            ResolveKitRuntimeLogger.log("Adopting orphaned turn from SSE event turn_id=\(turnID)")
            activeTurnID = turnID
        }

        switch envelope.type {
        case "assistant_text_delta":
            if let payload: ResolveKitTextDelta = decodePayload(envelope.payload) {
                activeAssistantDraft = payload.accumulated
                upsertAssistantDraft(payload.accumulated)
            }
        case "tool_call_request":
            guard let payload: ResolveKitToolCallRequest = decodePayload(envelope.payload) else { return }
            enqueueToolCallRequest(payload)
        case "turn_complete":
            if let payload: ResolveKitTurnComplete = decodePayload(envelope.payload) {
                upsertAssistantDraft(payload.fullText)
            }
            finalizeUnresolvedToolCallsAsTimedOut(reason: "Timed out")
            isTurnInProgress = false
            activeAssistantDraft = ""
            activeAssistantMessageID = nil
            activeTurnID = nil
        case "error":
            if let payload: ResolveKitServerErrorPayload = decodePayload(envelope.payload) {
                ResolveKitRuntimeLogger.log(
                    "Server error frame code=\(payload.code) recoverable=\(payload.recoverable) message=\(payload.message)"
                )
                if payload.code == "chat_unavailable" {
                    presentChatUnavailable()
                    return
                }
                if payload.code == "superseded" {
                    // A newer connection has taken over — silently let this connection die.
                    return
                }
                lastError = payload.message
                presentChatPresentationError(rawMessage: payload.message)
                if payload.message.lowercased().contains("timeout") {
                    finalizeUnresolvedToolCallsAsTimedOut(reason: payload.message)
                }
                if !payload.recoverable {
                    connectionState = .failed
                }
            }
            isTurnInProgress = false
            activeTurnID = nil
        default:
            break
        }
    }

    private func enqueueToolCallRequest(_ request: ResolveKitToolCallRequest) {
        guard !processedToolCallIDs.contains(request.callID) else {
            ResolveKitRuntimeLogger.log("Skipping duplicate tool_call_request call_id=\(request.callID)")
            return
        }
        processedToolCallIDs.insert(request.callID)
        collectingToolCalls.append(request)
        guard collectionTask == nil else { return }
        let delayMilliseconds = toolBatchCoalescingDelayMilliseconds

        collectionTask = Task { [weak self, delayMilliseconds] in
            guard let self else { return }
            await ResolveKitCompatibility.sleep(milliseconds: delayMilliseconds)
            await MainActor.run {
                self.flushCollectedToolCalls()
            }
        }
    }

    private func flushCollectedToolCalls() {
        collectionTask?.cancel()
        collectionTask = nil
        guard !collectingToolCalls.isEmpty else { return }

        let batch = collectingToolCalls
        collectingToolCalls = []

        if activeBatchRequests.isEmpty && batchStateAllowsImmediatePresentation {
            presentBatch(batch)
        } else {
            queuedBatches.append(batch)
        }
    }

    private var batchStateAllowsImmediatePresentation: Bool {
        switch toolCallBatchState {
        case .idle, .finished:
            return true
        case .awaitingApproval, .approved, .declined, .executing:
            return false
        }
    }

    private func presentBatch(_ batch: [ResolveKitToolCallRequest]) {
        guard !batch.isEmpty else { return }
        let batchID = UUID()
        activeBatchID = batchID
        activeBatchRequests = batch
        let items = batch.map {
            ToolCallChecklistItem(
                id: $0.callID,
                functionName: $0.functionName,
                humanDescription: $0.humanDescription,
                status: .pendingApproval
            )
        }
        toolCallChecklist = items
        setToolCallBatchState(.awaitingApproval)
        toolCallBatches.append(
            ToolCallChecklistBatch(
                id: batchID,
                items: items,
                state: toolCallBatchState,
                createdAt: Date()
            )
        )
        syncPendingToolCallCompatibility()
    }

    private func presentNextQueuedBatchIfNeeded() {
        guard !queuedBatches.isEmpty else { return }
        let next = queuedBatches.removeFirst()
        presentBatch(next)
    }

    private func updateChecklistStatus(for callIDs: [String], to status: ResolveKitToolCallItemStatus) {
        let idSet = Set(callIDs)
        toolCallChecklist = toolCallChecklist.map { item in
            guard idSet.contains(item.id) else { return item }
            return ToolCallChecklistItem(
                id: item.id,
                functionName: item.functionName,
                humanDescription: item.humanDescription,
                status: status,
                createdAt: item.createdAt
            )
        }
        syncActiveBatchHistory(items: toolCallChecklist)
        syncPendingToolCallCompatibility()
    }

    private func request(forCallID callID: String) -> ResolveKitToolCallRequest? {
        activeBatchRequests.first(where: { $0.callID == callID })
    }

    private func syncPendingToolCallCompatibility() {
        guard let item = toolCallChecklist.first(where: { $0.status == .pendingApproval }),
              let req = request(forCallID: item.id) else {
            pendingToolCall = nil
            return
        }

        pendingToolCall = ResolveKitPendingToolCall(
            id: req.callID,
            functionName: req.functionName,
            arguments: req.arguments,
            timeoutSeconds: req.timeoutSeconds,
            humanDescription: req.humanDescription
        )
    }

    private func executeToolCall(_ call: ResolveKitToolCallRequest) async -> ResolveKitToolResultPayload {
        let context = ResolveKitFunctionContext(sessionID: session?.id ?? "", requestID: call.callID)
        do {
            let value = try await registry.dispatch(
                functionName: call.functionName,
                arguments: call.arguments,
                context: context
            )
            return ResolveKitToolResultPayload(callID: call.callID, status: .success, result: value)
        } catch ResolveKitFunctionError.unknownFunction(let name) {
            return ResolveKitToolResultPayload(callID: call.callID, status: .error, error: "Unknown function: \(name)")
        } catch {
            return ResolveKitToolResultPayload(callID: call.callID, status: .error, error: error.localizedDescription)
        }
    }

    private func executeBatchStep(_ call: ResolveKitToolCallRequest) async -> BatchExecutionEvent {
        guard call.timeoutSeconds > 0 else {
            return await executeBatchStepWithoutTimeout(call)
        }

        return await withTaskGroup(of: BatchExecutionEvent.self) { group in
            group.addTask { [weak self] in
                guard let self else {
                    return .failed(callID: call.callID, error: "Runtime deallocated")
                }
                return await self.executeBatchStepWithoutTimeout(call)
            }
            group.addTask { [weak self] in
                let timeoutSeconds = call.timeoutSeconds
                await ResolveKitCompatibility.sleep(seconds: timeoutSeconds)
                guard !Task.isCancelled else {
                    return .cancelled(callID: call.callID, reason: nil)
                }
                guard let self else {
                    return .failed(callID: call.callID, error: "Runtime deallocated")
                }
                let reason = "Timed out after \(timeoutSeconds)s"
                if self.sendToolResultsEnabled {
                    let payload = ResolveKitToolResultPayload(
                        callID: call.callID,
                        status: .error,
                        result: nil,
                        error: reason
                    )
                    _ = await self.deliverToolResultReliably(payload)
                }
                return .cancelled(callID: call.callID, reason: reason)
            }

            let first = await group.next() ?? .failed(callID: call.callID, error: "Unknown execution error")
            group.cancelAll()
            return first
        }
    }

    private func executeBatchStepWithoutTimeout(_ call: ResolveKitToolCallRequest) async -> BatchExecutionEvent {
        let payload = await executeToolCall(call)
        if sendToolResultsEnabled {
            _ = await deliverToolResultReliably(payload)
        }
        if payload.status == .success {
            return .completed(callID: call.callID)
        }
        return .failed(callID: call.callID, error: payload.error ?? "Unknown tool error")
    }

    private func loadReusedSessionHistory(sessionID: String, chatCapabilityToken: String) async {
        do {
            let history = try await apiClient.listSessionMessages(
                sessionID: sessionID,
                chatCapabilityToken: chatCapabilityToken
            )
            let hydrated: [ResolveKitChatMessage] = history.compactMap { message in
                guard let content = message.content?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !content.isEmpty else {
                    return nil
                }
                let role: ResolveKitChatMessage.Role
                switch message.role {
                case "user":
                    role = .user
                case "assistant":
                    role = .assistant
                default:
                    role = .system
                }
                let createdAt = parseISODate(message.createdAt) ?? Date()
                return ResolveKitChatMessage(
                    role: role,
                    text: content,
                    createdAt: createdAt
                )
            }
            messages = hydrated
            // If we were mid-turn but the server already has an assistant reply as the last
            // message, the turn completed while we were disconnected — clear the stale state.
            if isTurnInProgress, hydrated.last?.role == .assistant {
                ResolveKitRuntimeLogger.log("Clearing stale in-progress turn: server history shows turn completed")
                finalizeUnresolvedToolCallsAsTimedOut(reason: "Completed while disconnected")
                isTurnInProgress = false
                activeAssistantDraft = ""
                activeAssistantMessageID = nil
                activeTurnID = nil
            }
        } catch {
            ResolveKitRuntimeLogger.log("Failed to load reused session history: \(error.localizedDescription)")
        }
    }

    /// Called after a lightweight reconnect when a turn was in progress.
    /// Waits briefly for outbox frames to arrive via WS, then polls the server
    /// to catch any turn completion that happened while we were disconnected.
    private func reconcileInProgressTurnAfterReconnect() async {
        await ResolveKitCompatibility.sleep(seconds: 1.5)
        guard isTurnInProgress, let session else { return }
        do {
            let history = try await apiClient.listSessionMessages(
                sessionID: session.id,
                chatCapabilityToken: session.chatCapabilityToken
            )
            let serverMessages: [ResolveKitChatMessage] = history.compactMap { message in
                guard let content = message.content?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !content.isEmpty else { return nil }
                let role: ResolveKitChatMessage.Role = message.role == "user" ? .user : .assistant
                return ResolveKitChatMessage(role: role, text: content, createdAt: parseISODate(message.createdAt) ?? Date())
            }
            guard let lastServer = serverMessages.last, lastServer.role == .assistant else { return }
            // Turn has completed on the server — surface the response if we don't already have it.
            let localAssistantTexts = Set(messages.filter { $0.role == .assistant }.map(\.text))
            if !localAssistantTexts.contains(lastServer.text) {
                upsertAssistantDraft(lastServer.text)
            }
            ResolveKitRuntimeLogger.log("Reconciled missed turn completion after reconnect")
            finalizeUnresolvedToolCallsAsTimedOut(reason: "Completed while disconnected")
            isTurnInProgress = false
            activeAssistantDraft = ""
            activeAssistantMessageID = nil
            activeTurnID = nil
        } catch {
            ResolveKitRuntimeLogger.log("Failed to reconcile in-progress turn after reconnect: \(error.localizedDescription)")
        }
    }

    private func parseISODate(_ value: String) -> Date? {
        let withFractionalSeconds = ISO8601DateFormatter()
        withFractionalSeconds.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let parsed = withFractionalSeconds.date(from: value) {
            return parsed
        }
        let withoutFractionalSeconds = ISO8601DateFormatter()
        withoutFractionalSeconds.formatOptions = [.withInternetDateTime]
        return withoutFractionalSeconds.date(from: value)
    }

    private func upsertAssistantDraft(_ text: String) {
        if let activeID = activeAssistantMessageID,
           let index = messages.firstIndex(where: { $0.id == activeID && $0.role == .assistant }) {
            let existing = messages[index]
            messages[index] = .init(id: existing.id, role: .assistant, text: text, createdAt: existing.createdAt)
            return
        }

        let message = ResolveKitChatMessage(role: .assistant, text: text)
        activeAssistantMessageID = message.id
        messages.append(message)
    }

    private func decodePayload<T: Decodable>(_ payload: JSONObject) -> T? {
        do {
            let data = try JSONEncoder().encode(payload)
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    private func resetToolCallFlowForNewTurn() {
        collectionTask?.cancel()
        collectionTask = nil
        collectingToolCalls = []
        queuedBatches = []
        activeBatchRequests = []
        activeBatchID = nil
        toolCallChecklist = []
        toolCallBatches = []
        setToolCallBatchState(.idle)
        pendingToolCall = nil
        processedToolCallIDs = []
    }

    private func setToolCallBatchState(_ newState: ResolveKitToolCallBatchState) {
        toolCallBatchState = newState
        syncActiveBatchHistory(state: newState)
    }

    private func syncActiveBatchHistory(
        items: [ToolCallChecklistItem]? = nil,
        state: ResolveKitToolCallBatchState? = nil
    ) {
        guard let activeBatchID else { return }
        toolCallBatches = toolCallBatches.map { batch in
            guard batch.id == activeBatchID else { return batch }
            return ToolCallChecklistBatch(
                id: batch.id,
                items: items ?? batch.items,
                state: state ?? batch.state,
                createdAt: batch.createdAt
            )
        }
    }

    private func finalizeUnresolvedToolCallsAsTimedOut(reason: String) {
        guard !activeBatchRequests.isEmpty else { return }
        guard toolCallBatchState == .awaitingApproval || toolCallBatchState == .executing || toolCallBatchState == .approved else { return }

        let unresolvedIDs = toolCallChecklist
            .filter { item in
                switch item.status {
                case .pendingApproval, .running:
                    return true
                case .completed, .cancelled, .failed:
                    return false
                }
            }
            .map(\.id)

        if !unresolvedIDs.isEmpty {
            updateChecklistStatus(for: unresolvedIDs, to: .cancelled(reason: reason))
        }

        pendingToolCall = nil
        setToolCallBatchState(.finished)
        activeBatchID = nil
        activeBatchRequests = []
        presentNextQueuedBatchIfNeeded()
    }

    private func awaitTurnConfirmationOrFail(lastError: String?, maxAttempts: Int) async {
        let timeout: TimeInterval = 3.0
        let start = Date()
        while Date().timeIntervalSince(start) < timeout {
            if activeTurnID != nil {
                ResolveKitRuntimeLogger.log("Turn confirmed via SSE after POST failure — server received the message")
                return
            }
            await ResolveKitCompatibility.sleep(milliseconds: 200)
        }
        failTurn(lastError ?? "Message send failed after \(maxAttempts) attempts")
    }

    private func failTurn(_ message: String) {
        lastError = message
        presentChatPresentationError(rawMessage: message)
        isTurnInProgress = false
        activeAssistantMessageID = nil
        connectionState = .failed
        activeTurnID = nil
    }

    private func presentChatUnavailable() {
        ResolveKitRuntimeLogger.log("Presenting generic unavailable message to chat UI")
        lastError = unavailableMessage
        presentChatPresentationError(rawMessage: unavailableMessage)
        isTurnInProgress = false
        activeAssistantDraft = ""
        activeAssistantMessageID = nil
        activeTurnID = nil
    }

    public func setLocale(_ locale: String?) async {
        let resolved = ResolveKitLocaleResolver.resolve(
            locale: locale,
            preferredLocales: configuration.resolvedPreferredLocales()
        )
        currentLocale = resolved
        guard let session else { return }
        do {
            let localization = try await apiClient.sessionLocalization(
                sessionID: session.id,
                locale: resolved,
                chatCapabilityToken: session.chatCapabilityToken
            )
            currentLocale = localization.locale
            chatTitle = localization.chatTitle
            messagePlaceholder = localization.messagePlaceholder
            reconcileInitialMessageAfterReuse(expected: localization.initialMessage)
        } catch {
            // Locale override for model replies still works because currentLocale is attached to outgoing turns.
        }
    }

    private func reconcileInitialMessageAfterReuse(expected: String) {
        let trimmed = expected.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let hasUserMessages = messages.contains(where: { $0.role == .user })
        guard !hasUserMessages else { return }
        if messages.isEmpty {
            messages.append(.init(role: .assistant, text: trimmed))
            return
        }
        if messages.count == 1, messages[0].role == .assistant {
            let only = messages[0]
            if only.text != trimmed {
                messages[0] = .init(id: only.id, role: .assistant, text: trimmed, createdAt: only.createdAt)
            }
        }
    }

    private func adoptSession(_ newSession: ResolveKitSession) {
        if let previous = session,
           previous.id != newSession.id,
           !pendingToolResults.isEmpty {
            ResolveKitRuntimeLogger.log(
                "Session changed from \(previous.id) to \(newSession.id), dropping \(pendingToolResults.count) pending tool result(s)"
            )
            pendingToolResults = []
        }
        session = newSession
        if lastReceivedEventID == nil {
            lastReceivedEventID = UserDefaults.standard.string(forKey: "rk_cursor_\(newSession.id)")
        }
    }

    @discardableResult
    private func deliverToolResultReliably(_ payload: ResolveKitToolResultPayload) async -> Bool {
        guard sendToolResultsEnabled else { return true }
        queuePendingToolResult(payload)
        return await flushPendingToolResults(reason: "immediate delivery retry")
    }

    private func queuePendingToolResult(_ payload: ResolveKitToolResultPayload) {
        if let index = pendingToolResults.firstIndex(where: { $0.callID == payload.callID }) {
            pendingToolResults[index] = payload
        } else {
            pendingToolResults.append(payload)
        }
        ResolveKitRuntimeLogger.log("Queued tool result call_id=\(payload.callID) for retry")
    }

    private func submitToolResultViaHTTP(
        _ payload: ResolveKitToolResultPayload,
        session: ResolveKitSession
    ) async -> Bool {
        guard let activeTurnID else {
            return false
        }
        do {
            try await apiClient.submitToolResult(
                sessionID: session.id,
                requestBody: ResolveKitToolResultRequest(
                    turnID: activeTurnID,
                    idempotencyKey: payload.callID,
                    callID: payload.callID,
                    status: payload.status,
                    result: payload.result,
                    error: payload.error
                ),
                chatCapabilityToken: session.chatCapabilityToken
            )
            return true
        } catch ResolveKitAPIClientError.serverError(let statusCode, _) where statusCode == 404 || statusCode == 410 {
            // Treat "not pending" and "session expired" as terminal for this call.
            ResolveKitRuntimeLogger.log(
                "HTTP tool_result submit terminal status=\(statusCode) for \(payload.callID), dropping retry"
            )
            return true
        } catch {
            ResolveKitRuntimeLogger.log("HTTP tool_result submit failed for \(payload.callID): \(error.localizedDescription)")
            return false
        }
    }

    @discardableResult
    private func flushPendingToolResults(reason: String) async -> Bool {
        guard !pendingToolResults.isEmpty else { return true }
        guard !isFlushingPendingToolResults else { return false }
        guard let session else {
            ResolveKitRuntimeLogger.log("Pending tool results retained (\(pendingToolResults.count)); no active session")
            return false
        }

        isFlushingPendingToolResults = true
        defer { isFlushingPendingToolResults = false }

        var remaining: [ResolveKitToolResultPayload] = []
        for payload in pendingToolResults {
            if await submitToolResultViaHTTP(payload, session: session) {
                continue
            }
            remaining.append(payload)
        }

        if remaining.count != pendingToolResults.count {
            ResolveKitRuntimeLogger.log(
                "Flushed \(pendingToolResults.count - remaining.count) pending tool result(s) (\(reason))"
            )
        }
        pendingToolResults = remaining
        return remaining.isEmpty
    }
}

#if DEBUG
extension ResolveKitRuntime {
    func _debugRegisterFunctions(_ functions: [(any AnyResolveKitFunction.Type)]) async throws {
        await registry.reset()
        try await registry.register(functions)
    }

    func _debugReceiveToolCallRequest(_ request: ResolveKitToolCallRequest) {
        enqueueToolCallRequest(request)
    }

    func _debugWaitForCoalescingWindow() async {
        await ResolveKitCompatibility.sleep(milliseconds: toolBatchCoalescingDelayMilliseconds + 80)
        flushCollectedToolCalls()
    }

    func _debugHandleTurnComplete(fullText: String = "") {
        if !fullText.isEmpty {
            upsertAssistantDraft(fullText)
        }
        finalizeUnresolvedToolCallsAsTimedOut(reason: "Timed out")
        isTurnInProgress = false
        activeAssistantDraft = ""
        activeAssistantMessageID = nil
    }

    func _debugSetTurnInProgress(_ inProgress: Bool) {
        isTurnInProgress = inProgress
    }

    func _debugSetSession(_ session: ResolveKitSession?) {
        if let session {
            adoptSession(session)
        } else {
            self.session = nil
            pendingToolResults = []
        }
    }

    func _debugSetActiveTurnID(_ turnID: String?) {
        activeTurnID = turnID
    }

    func _debugPendingToolResultCallIDs() -> [String] {
        pendingToolResults.map(\.callID)
    }

    func _debugFlushPendingToolResults() async {
        _ = await flushPendingToolResults(reason: "debug flush")
    }

    func _debugHandleServerEnvelope(_ envelope: ResolveKitEnvelope) async {
        await handleServerEnvelope(envelope)
    }

    func _debugSetChatTitle(_ title: String) {
        chatTitle = title
    }

    func _debugResetToolCallFlowForNewTurn() {
        resetToolCallFlowForNewTurn()
    }

    func _debugSetConnectionState(_ state: ResolveKitConnectionState) {
        connectionState = state
    }

    func _debugHandlePathSatisfaction(_ isSatisfied: Bool) {
        onPathSatisfactionStable(isSatisfied)
    }

    func _debugLastReconnectTrigger() -> String? {
        lastReconnectTrigger?.rawValue
    }

    func _debugConsumeTransportFailure(_ message: String) async {
        await handleTransportFailure(message)
    }

    func _debugChatPresentationError() -> ResolveKitChatPresentationError? {
        chatPresentationError
    }

    func _debugSetChatPresentationError(_ error: ResolveKitChatPresentationError?) {
        chatPresentationError = error
    }

    func _debugSetInitialFetchCompleted(_ completed: Bool) {
        initialFetchCompleted = completed
    }
}
#endif

private enum BatchExecutionEvent: Sendable {
    case completed(callID: String)
    case cancelled(callID: String, reason: String?)
    case failed(callID: String, error: String)
}
