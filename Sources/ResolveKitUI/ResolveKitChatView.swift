import SwiftUI
import ResolveKitCore
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

private enum ResolveKitChatViewLogger {
    static func log(_ message: String) {
        print("[ResolveKit][ChatView] \(message)")
    }
}

struct ResolveKitChatComposerFocusState {
    var isFocused = false

    @discardableResult
    mutating func dismiss() -> Bool {
        guard isFocused else { return false }
        isFocused = false
        return true
    }

    @discardableResult
    mutating func updateFocus(_ newValue: Bool) -> Bool {
        isFocused = newValue
        return false
    }
}

enum ResolveKitChatInitialPresentationPhase {
    case waitingForInitialFetch
    case renderingInitialContent
    case finished

    var showsChatContent: Bool {
        self != .waitingForInitialFetch
    }

    var allowsLiveAutoScroll: Bool {
        self == .finished
    }

    @discardableResult
    mutating func revealInitialContent() -> Bool {
        guard self == .waitingForInitialFetch else { return false }
        self = .renderingInitialContent
        return true
    }

    @discardableResult
    mutating func finishInitialScroll() -> Bool {
        guard self == .renderingInitialContent else { return false }
        self = .finished
        return true
    }

    @discardableResult
    mutating func resetForReload() -> Bool {
        guard self != .waitingForInitialFetch else { return false }
        self = .waitingForInitialFetch
        return true
    }
}

enum ResolveKitScrollKeyboardDismissBehavior: Equatable {
    case interactive
}

extension ResolveKitScrollKeyboardDismissBehavior {
    static let current: ResolveKitScrollKeyboardDismissBehavior = .interactive
}

enum ResolveKitComposerGestureDismissal {
    private static let minimumDownwardTranslation: CGFloat = 18
    private static let minimumUpwardTranslation: CGFloat = -18

    static func shouldDismissKeyboard(translation: CGSize) -> Bool {
        translation.height >= minimumDownwardTranslation && abs(translation.height) > abs(translation.width)
    }

    static func shouldFocusKeyboard(translation: CGSize) -> Bool {
        translation.height <= minimumUpwardTranslation && abs(translation.height) > abs(translation.width)
    }
}

enum ResolveKitInitialComposerFocusPolicy {
    static func shouldFocusComposer(initialMessageCount: Int) -> Bool {
        initialMessageCount == 1
    }
}

enum ResolveKitInitialPresentationScrollPolicy {
    static func requiresInitialScroll(anchorMaxY: CGFloat, viewportHeight: CGFloat) -> Bool {
        guard anchorMaxY.isFinite, viewportHeight.isFinite else { return true }
        return anchorMaxY > viewportHeight
    }
}

enum ResolveKitThinkingIndicatorVisibilityPolicy {
    static func shouldShowThinkingIndicator(
        initialFetchCompleted: Bool,
        isTurnInProgress: Bool,
        toolChecklistCount: Int,
        presentationError: ResolveKitChatPresentationError? = nil
    ) -> Bool {
        if presentationError?.hidesAssistantDraft == true {
            return false
        }

        if !initialFetchCompleted {
            return true
        }

        return isTurnInProgress && toolChecklistCount == 0
    }
}

enum ResolveKitThinkingIndicatorTransition: Equatable {
    case hide
    case scheduleShow(delayMilliseconds: UInt64)
}

enum ResolveKitThinkingIndicatorTransitionPolicy {
    static func transition(for isVisible: Bool) -> ResolveKitThinkingIndicatorTransition {
        if isVisible {
            return .scheduleShow(delayMilliseconds: 500)
        }

        return .hide
    }
}

enum ResolveKitThinkingIndicatorMorphPolicy {
    static func morphTargetAssistantID(
        showThinkingIndicator: Bool,
        initialFetchCompleted: Bool,
        lastMessage: ResolveKitChatMessage?,
        presentationError: ResolveKitChatPresentationError? = nil
    ) -> UUID? {
        if presentationError?.hidesAssistantDraft == true {
            return nil
        }

        guard showThinkingIndicator else { return nil }
        guard initialFetchCompleted else { return nil }
        guard let lastMessage, lastMessage.role == .assistant else { return nil }
        return lastMessage.id
    }
}

enum ResolveKitChatComposerLayout {
    private static let closedBottomGap: CGFloat = 4
    private static let timelineBottomBreathingRoom: CGFloat = 12

    static func dockBottomInset() -> CGFloat {
        closedBottomGap
    }

    static func timelineBottomReserve(forComposerHeight composerHeight: CGFloat) -> CGFloat {
        composerHeight + timelineBottomBreathingRoom
    }
}

enum ResolveKitComposerInteractivityPolicy {
    static func isEnabled(initialFetchCompleted: Bool, isTurnInProgress: Bool) -> Bool {
        initialFetchCompleted && !isTurnInProgress
    }
}

struct ResolveKitChatInitialScrollPlan {
    struct Step: Equatable {
        let delayMilliseconds: UInt64
        let animated: Bool
    }

    let steps: [Step]

    static let initialPresentation = ResolveKitChatInitialScrollPlan(
        steps: [
            Step(delayMilliseconds: 200, animated: true),
            Step(delayMilliseconds: 420, animated: true)
        ]
    )

    static let messageUpdate = ResolveKitChatInitialScrollPlan(
        steps: [
            Step(delayMilliseconds: 20, animated: true),
            Step(delayMilliseconds: 140, animated: true)
        ]
    )

    static let keyboardDismiss = ResolveKitChatInitialScrollPlan(
        steps: [
            Step(delayMilliseconds: 0, animated: true),
            Step(delayMilliseconds: 120, animated: true)
        ]
    )
}

public struct ResolveKitChatView: View {
    private struct ScrollTrigger: Hashable {
        let messageCount: Int
        let lastMessageID: UUID?
        let toolBatchCount: Int
        let presentationErrorMessage: String?
    }
    private enum TimelineEntry: Identifiable {
        case message(ResolveKitChatMessage)
        case toolBatch(ToolCallChecklistBatch)

        var id: String {
            switch self {
            case .message(let message):
                return "msg-\(message.id.uuidString)"
            case .toolBatch(let batch):
                return "tool-\(batch.id.uuidString)"
            }
        }

        var createdAt: Date {
            switch self {
            case .message(let message):
                return message.createdAt
            case .toolBatch(let batch):
                return batch.createdAt
            }
        }
    }

    private let bottomAnchorID = "chat-bottom-anchor"
    private let scrollSpring = Animation.spring(response: 0.5, dampingFraction: 0.82, blendDuration: 0.15)
    private let morphBubbleID = "assistant-response-bubble-morph"
    private let scrollViewportCoordinateSpace = "resolvekit-chat-scroll"
    @ObservedObject private var runtime: ResolveKitRuntime
    @Environment(\.colorScheme) private var systemColorScheme
    @State private var draft = ""
    @State private var composerFocusState = ResolveKitChatComposerFocusState()
    @State private var showThinkingIndicator = false
    @State private var thinkingDelayTask: Task<Void, Never>?
    @State private var isPinnedToBottom = true
    @State private var bottomAnchorMaxY: CGFloat = .infinity
    @State private var composerHeight: CGFloat = 0
    @State private var initialPresentationPhase = ResolveKitChatInitialPresentationPhase.waitingForInitialFetch
    @State private var initialContentOpacity = 0.0
    @FocusState private var isComposerFocused: Bool
    @Namespace private var bubbleMorphNamespace

    public init(runtime: ResolveKitRuntime) {
        self.runtime = runtime
    }

    public var body: some View {
        GeometryReader { geometry in
            let safeAreaTop = geometry.safeAreaInsets.top
            let contentTopInset = topContentInset(safeAreaTop: safeAreaTop)
            let reservedHeight = composerReservedHeight()
            let composerBottomInset = composerBottomSpacing()
            let showsChatContent = initialPresentationPhase.showsChatContent

            ScrollViewReader { proxy in
                Group {
                    if showsChatContent {
                        ScrollView {
                            timelineContent(contentTopInset: contentTopInset, reservedHeight: reservedHeight)
                        }
                        .opacity(initialPresentationPhase.allowsLiveAutoScroll ? 1 : initialContentOpacity)
                    } else {
                        initialLoadingContent(contentTopInset: contentTopInset)
                    }
                }
                .ignoresSafeArea(edges: .top)
                .coordinateSpace(name: scrollViewportCoordinateSpace)
                .resolveKitScrollDismissesKeyboard()
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    composer
                        .padding(.horizontal)
                        .padding(.top, 8)
                        .padding(.bottom, composerBottomInset)
                        .background {
                            GeometryReader { composerGeometry in
                                Color.clear.preference(
                                    key: ResolveKitComposerHeightPreferenceKey.self,
                                    value: composerGeometry.size.height
                                )
                            }
                        }
                        .background(.clear)
                }
                .task(id: scrollTrigger) {
                    guard initialPresentationPhase.allowsLiveAutoScroll else { return }
                    guard isPinnedToBottom else { return }
                    await scrollToBottom(using: proxy, plan: .messageUpdate)
                }
                .onChange(of: showThinkingIndicator) { isVisible in
                    guard initialPresentationPhase.allowsLiveAutoScroll else { return }
                    guard isPinnedToBottom else { return }
                    if isVisible {
                        withAnimation(scrollSpring) {
                            proxy.scrollTo(bottomAnchorID, anchor: .bottom)
                        }
                        Task { @MainActor in
                            await ResolveKitCompatibility.sleep(milliseconds: 70)
                            withAnimation(scrollSpring) {
                                proxy.scrollTo(bottomAnchorID, anchor: .bottom)
                            }
                        }
                    } else {
                        withAnimation(scrollSpring) {
                            proxy.scrollTo(bottomAnchorID, anchor: .bottom)
                        }
                    }
                }
                .task(id: runtime.initialFetchCompleted) {
                    guard runtime.initialFetchCompleted else { return }
                    guard initialPresentationPhase.revealInitialContent() else { return }

                    // Give SwiftUI one render turn to lay out the revealed timeline before deciding whether scrolling is needed.
                    await Task.yield()
                    let shouldFocusComposer = ResolveKitInitialComposerFocusPolicy.shouldFocusComposer(
                        initialMessageCount: runtime.messages.count
                    )
                    let requiresInitialScroll = ResolveKitInitialPresentationScrollPolicy.requiresInitialScroll(
                        anchorMaxY: bottomAnchorMaxY,
                        viewportHeight: geometry.size.height
                    )

                    withAnimation(.easeOut(duration: 0.28)) {
                        initialContentOpacity = 1
                    }

                    if requiresInitialScroll {
                        await scrollToBottom(using: proxy, plan: .initialPresentation)
                    }

                    _ = initialPresentationPhase.finishInitialScroll()
                    isPinnedToBottom = true
                    if shouldFocusComposer && requiresInitialScroll {
                        isComposerFocused = true
                    }
                }
                .onChange(of: runtime.initialFetchCompleted) { completed in
                    guard completed == false else { return }
                    guard initialPresentationPhase.resetForReload() else { return }
                    initialContentOpacity = 0
                    isPinnedToBottom = true
                }
                .onPreferenceChange(ResolveKitBottomAnchorMaxYPreferenceKey.self) { anchorMaxY in
                    guard initialPresentationPhase.showsChatContent else { return }
                    bottomAnchorMaxY = anchorMaxY
                    isPinnedToBottom = ResolveKitChatScrollPinning.isNearBottom(
                        anchorMaxY: anchorMaxY,
                        viewportHeight: geometry.size.height,
                        tolerance: max(80, composerHeight + 24)
                    )
                }
                .onPreferenceChange(ResolveKitComposerHeightPreferenceKey.self) { height in
                    guard initialPresentationPhase.allowsLiveAutoScroll else { return }
                    let previousHeight = composerHeight
                    composerHeight = height
                    guard isPinnedToBottom else { return }
                    guard abs(previousHeight - height) > 0.5 else { return }

                    Task { @MainActor in
                        withAnimation(scrollSpring) {
                            proxy.scrollTo(bottomAnchorID, anchor: .bottom)
                        }
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: ResolveKitForceScrollToBottomNotification.name)) { _ in
                    guard initialPresentationPhase.allowsLiveAutoScroll else { return }
                    Task {
                        await scrollToBottom(using: proxy, plan: .keyboardDismiss)
                    }
                }
                .background {
                    resolvedPalette.screenBackgroundColor
                        .ignoresSafeArea()
                }
                .preferredColorScheme(preferredColorScheme)
                .overlay(alignment: .top) {
                    topNavigationFade(height: topFadeHeight(safeAreaTop: safeAreaTop))
                }
            }
        }
        .task {
            do {
                try await runtime.start()
            } catch {
                // Runtime already updates published error state.
            }
        }
        .task(id: isThinkingVisibleRaw) {
            await updateThinkingIndicatorVisibility(for: isThinkingVisibleRaw)
        }
        .onDisappear {
            thinkingDelayTask?.cancel()
            thinkingDelayTask = nil
        }
        .onChange(of: isComposerFocused) { isFocused in
            _ = composerFocusState.updateFocus(isFocused)
            guard isFocused else { return }
            NotificationCenter.default.post(name: ResolveKitForceScrollToBottomNotification.name, object: nil)
        }
        .animation(
            .spring(response: 0.38, dampingFraction: 0.72, blendDuration: 0.12),
            value: runtime.messages.map { $0.id.uuidString }
                + runtime.toolCallBatches.map { $0.id.uuidString }
                + [runtime.chatPresentationError?.message ?? ""]
        )
    }

    private var isThinkingVisibleRaw: Bool {
        ResolveKitThinkingIndicatorVisibilityPolicy.shouldShowThinkingIndicator(
            initialFetchCompleted: runtime.initialFetchCompleted,
            isTurnInProgress: runtime.isTurnInProgress,
            toolChecklistCount: runtime.toolCallChecklist.count,
            presentationError: runtime.chatPresentationError
        )
    }

    private var shouldShowThinkingIndicator: Bool {
        showThinkingIndicator && morphTargetAssistantID == nil
    }

    @MainActor
    private func updateThinkingIndicatorVisibility(for isVisible: Bool) async {
        switch ResolveKitThinkingIndicatorTransitionPolicy.transition(for: isVisible) {
        case .hide:
            thinkingDelayTask?.cancel()
            thinkingDelayTask = nil
            withAnimation(.easeOut(duration: 0.18)) {
                showThinkingIndicator = false
            }
        case .scheduleShow(let delayMilliseconds):
            thinkingDelayTask?.cancel()
            thinkingDelayTask = Task { @MainActor in
                await ResolveKitCompatibility.sleep(milliseconds: delayMilliseconds)
                guard !Task.isCancelled, isThinkingVisibleRaw else { return }
                withAnimation(.spring(response: 0.38, dampingFraction: 0.72, blendDuration: 0.12)) {
                    showThinkingIndicator = true
                }
            }
        }
    }

    private var morphTargetAssistantID: UUID? {
        ResolveKitThinkingIndicatorMorphPolicy.morphTargetAssistantID(
            showThinkingIndicator: showThinkingIndicator,
            initialFetchCompleted: runtime.initialFetchCompleted,
            lastMessage: runtime.messages.last,
            presentationError: runtime.chatPresentationError
        )
    }

    private var scrollTrigger: ScrollTrigger {
        ScrollTrigger(
            messageCount: runtime.messages.count,
            lastMessageID: runtime.messages.last?.id,
            toolBatchCount: runtime.toolCallBatches.count,
            presentationErrorMessage: runtime.chatPresentationError?.message
        )
    }

    private var timelineEntries: [TimelineEntry] {
        let merged = runtime.messages.map(TimelineEntry.message) + runtime.toolCallBatches.map(TimelineEntry.toolBatch)
        return merged.sorted { lhs, rhs in
            if lhs.createdAt == rhs.createdAt {
                return lhs.id < rhs.id
            }
            return lhs.createdAt < rhs.createdAt
        }
    }

    private func topNavigationFade(height: CGFloat) -> some View {
        Rectangle()
            .fill(.ultraThinMaterial)
            .overlay {
                LinearGradient(
                    stops: [
                        .init(color: resolvedPalette.screenBackgroundColor.opacity(0.34), location: 0),
                        .init(color: resolvedPalette.screenBackgroundColor.opacity(0.16), location: 0.45),
                        .init(color: resolvedPalette.screenBackgroundColor.opacity(0), location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .mask {
                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(0.95), location: 0),
                        .init(color: .black.opacity(0.72), location: 0.45),
                        .init(color: .clear, location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .frame(height: height)
            .ignoresSafeArea(edges: .top)
            .allowsHitTesting(false)
    }

    private func topContentInset(safeAreaTop: CGFloat) -> CGFloat {
        safeAreaTop + 16
    }

    private func topFadeHeight(safeAreaTop: CGFloat) -> CGFloat {
        topContentInset(safeAreaTop: safeAreaTop) + 16
    }

    private func composerBottomSpacing() -> CGFloat {
        ResolveKitChatComposerLayout.dockBottomInset()
    }

    private func composerReservedHeight() -> CGFloat {
        ResolveKitChatComposerLayout.timelineBottomReserve(forComposerHeight: composerHeight)
    }

    private func timelineContent(contentTopInset: CGFloat, reservedHeight: CGFloat) -> some View {
        LazyVStack(alignment: .leading, spacing: 8) {
            ForEach(timelineEntries) { entry in
                timelineEntryView(entry)
            }
            if let presentationError = runtime.chatPresentationError {
                transientErrorBubble(presentationError)
            }
            if shouldShowThinkingIndicator {
                thinkingIndicator
                    .transition(
                        .asymmetric(
                            insertion: .scale(scale: 0.92, anchor: .leading).combined(with: .opacity),
                            removal: .opacity
                        )
                    )
            }
            bottomAnchorSpacer(reservedHeight: reservedHeight)
        }
        .padding(.leading, 16)
        .padding(.trailing, 16)
        .padding(.top, contentTopInset)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func initialLoadingContent(contentTopInset: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let presentationError = runtime.chatPresentationError {
                transientErrorBubble(presentationError)
                    .padding(.top, contentTopInset)
                    .padding(.horizontal, 16)
            } else if shouldShowThinkingIndicator {
                thinkingIndicator
                    .padding(.top, contentTopInset)
                    .padding(.horizontal, 16)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func timelineEntryView(_ entry: TimelineEntry) -> some View {
        Group {
            switch entry {
            case .message(let message):
                messageRow(message)
            case .toolBatch(let batch):
                toolBatchRow(batch)
            }
        }
        .transition(
            .asymmetric(
                insertion: .scale(scale: 0.92).combined(with: .opacity),
                removal: .opacity
            )
        )
    }

    private func bottomAnchorSpacer(reservedHeight: CGFloat) -> some View {
        Color.clear
            .frame(height: reservedHeight)
            .background {
                GeometryReader { anchorGeometry in
                    Color.clear.preference(
                        key: ResolveKitBottomAnchorMaxYPreferenceKey.self,
                        value: anchorGeometry.frame(in: .named(scrollViewportCoordinateSpace)).maxY
                    )
                }
            }
            .id(bottomAnchorID)
    }

    private func scrollToBottom(using proxy: ScrollViewProxy, plan: ResolveKitChatInitialScrollPlan) async {
        for step in plan.steps {
            if step.delayMilliseconds > 0 {
                await ResolveKitCompatibility.sleep(milliseconds: step.delayMilliseconds)
            }
            await MainActor.run {
                if step.animated {
                    withAnimation(scrollSpring) {
                        proxy.scrollTo(bottomAnchorID, anchor: .bottom)
                    }
                } else {
                    proxy.scrollTo(bottomAnchorID, anchor: .bottom)
                }
            }
        }
    }

    private var thinkingIndicator: some View {
        HStack {
            TypingIndicatorBubble(palette: resolvedPalette)
                .matchedGeometryEffect(
                    id: morphBubbleID,
                    in: bubbleMorphNamespace,
                    properties: .frame,
                    anchor: .leading
                )
            Spacer(minLength: 24)
        }
    }

    private func transientErrorBubble(_ error: ResolveKitChatPresentationError) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                Text("Something went wrong.")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(resolvedPalette.assistantBubbleTextColor)
                Text(error.message)
                    .foregroundStyle(resolvedPalette.assistantBubbleTextColor)
                Text(error.recoverySuggestion)
                    .font(.footnote)
                    .foregroundStyle(resolvedPalette.assistantBubbleTextColor.opacity(0.82))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(resolvedPalette.assistantBubbleBackgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            Spacer(minLength: 24)
        }
    }

    private func messageRow(_ message: ResolveKitChatMessage) -> some View {
        let isUser = message.role == .user
        let bubble = Text(message.text)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .foregroundStyle(isUser ? resolvedPalette.userBubbleTextColor : resolvedPalette.assistantBubbleTextColor)
            .background(
                isUser
                    ? resolvedPalette.userBubbleBackgroundColor
                    : resolvedPalette.assistantBubbleBackgroundColor
            )
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .contextMenu {
                Button("Copy") {
                    copyToClipboard(message.text)
                }
            }

        return HStack {
            if message.role == .user { Spacer(minLength: 24) }
            if message.role == .assistant && message.id == morphTargetAssistantID {
                bubble
                    .matchedGeometryEffect(
                        id: morphBubbleID,
                        in: bubbleMorphNamespace,
                        properties: .frame,
                        anchor: .leading
                    )
            } else {
                bubble
            }
            if message.role == .assistant { Spacer(minLength: 24) }
        }
    }

    private func toolBatchRow(_ batch: ToolCallChecklistBatch) -> some View {
        HStack {
            toolChecklistCard(batch)
                .frame(maxWidth: 560, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func toolChecklistCard(_ batch: ToolCallChecklistBatch) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Tool Requests")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(resolvedPalette.toolCardTitleColor)
                Spacer()
                Text(batchStateTitle(batch.state))
                    .font(.caption)
                    .foregroundStyle(resolvedPalette.statusTextColor)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 8)

            VStack(spacing: 0) {
                ForEach(Array(batch.items.enumerated()), id: \.element.id) { index, item in
                    checklistRow(item)
                    if index < batch.items.count - 1 {
                        Divider()
                            .padding(.leading, 44)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 10)

            if batch.state == .awaitingApproval {
                Divider()

                HStack(spacing: 10) {
                    Button("Decline All", role: .destructive) {
                        Task { await runtime.declineToolCallBatch() }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .disabled(runtime.toolCallBatchState != .awaitingApproval)

                    Button("Approve All") {
                        Task { await runtime.approveToolCallBatch() }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                    .disabled(runtime.toolCallBatchState != .awaitingApproval)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
        .background(resolvedPalette.toolCardBackgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(resolvedPalette.toolCardBorderColor, lineWidth: 1)
        )
    }

    private func checklistRow(_ item: ToolCallChecklistItem) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: icon(for: item.status))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(iconColor(for: item.status))
                .frame(width: 18, height: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.humanDescription.isEmpty ? "I will perform a requested action." : item.humanDescription)
                    .font(.subheadline)
                    .foregroundStyle(resolvedPalette.toolCardBodyColor)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Text(statusText(for: item.status))
                    .font(.caption)
                    .foregroundStyle(resolvedPalette.statusTextColor)
            }
            Spacer()
        }
        .padding(.vertical, 9)
    }

    private func batchStateTitle(_ state: ResolveKitToolCallBatchState) -> String {
        switch state {
        case .idle:
            return "Idle"
        case .awaitingApproval:
            return "Awaiting Approval"
        case .approved:
            return "Approved"
        case .declined:
            return "Declined"
        case .executing:
            return "Executing"
        case .finished:
            return "Finished"
        }
    }

    private func icon(for status: ResolveKitToolCallItemStatus) -> String {
        switch status {
        case .pendingApproval:
            return "clock.badge.questionmark"
        case .running:
            return "hourglass"
        case .completed:
            return "checkmark.circle.fill"
        case .cancelled:
            return "xmark.circle.fill"
        case .failed:
            return "exclamationmark.triangle.fill"
        }
    }

    private func iconColor(for status: ResolveKitToolCallItemStatus) -> Color {
        switch status {
        case .pendingApproval:
            return .secondary
        case .running:
            return .orange
        case .completed:
            return .green
        case .cancelled:
            return .secondary
        case .failed:
            return .red
        }
    }

    private func statusText(for status: ResolveKitToolCallItemStatus) -> String {
        switch status {
        case .pendingApproval:
            return "Awaiting approval"
        case .running:
            return "Running"
        case .completed:
            return "Completed"
        case .cancelled(let reason):
            return reason ?? "Cancelled"
        case .failed(let error):
            return "Failed: \(error)"
        }
    }

    private var isComposerLoading: Bool {
        !ResolveKitComposerInteractivityPolicy.isEnabled(
            initialFetchCompleted: runtime.initialFetchCompleted,
            isTurnInProgress: runtime.isTurnInProgress
        )
    }

    private var composer: some View {
        let placeholderColor = isComposerLoading
            ? resolvedPalette.composerPlaceholderColor.opacity(0.65)
            : resolvedPalette.composerPlaceholderColor

        return HStack(spacing: 10) {
            TextField(
                "",
                text: $draft,
                prompt: Text(runtime.messagePlaceholder).foregroundColor(placeholderColor)
            )
                .textFieldStyle(.plain)
                .focused($isComposerFocused)
                .onAppear {
                    guard initialPresentationPhase == .renderingInitialContent else { return }
                    guard ResolveKitInitialComposerFocusPolicy.shouldFocusComposer(initialMessageCount: runtime.messages.count) else {
                        return
                    }
                    isComposerFocused = true
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(composerFieldBackground(isLoading: isComposerLoading))
                .foregroundStyle(
                    isComposerLoading
                        ? resolvedPalette.composerTextColor.opacity(0.5)
                        : resolvedPalette.composerTextColor
                )
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(composerFieldBorder(isLoading: isComposerLoading))
                .disabled(isComposerLoading)
                .submitLabel(.send)
                .onSubmit {
                    sendDraftIfPossible()
                }
                .simultaneousGesture(
                    DragGesture(minimumDistance: 6)
                        .onEnded { value in
                            if ResolveKitComposerGestureDismissal.shouldFocusKeyboard(translation: value.translation) {
                                guard !isComposerFocused else { return }
                                isComposerFocused = true
                                return
                            }

                            guard isComposerFocused else { return }
                            guard ResolveKitComposerGestureDismissal.shouldDismissKeyboard(translation: value.translation) else {
                                return
                            }
                            guard dismissComposerIfNeeded() else { return }
                            NotificationCenter.default.post(
                                name: ResolveKitForceScrollToBottomNotification.name,
                                object: nil
                            )
                        }
                )

            Button("Send") {
                sendDraftIfPossible()
            }
            .foregroundStyle(isComposerLoading ? .secondary : .primary)
            .opacity(isComposerLoading ? 0.45 : 1)
            .disabled(isComposerLoading || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(composerSendButtonBackground)
            .clipShape(Capsule())
            .overlay(composerSendButtonBorder)
        }
        .padding(.horizontal, supportsLiquidGlassChrome ? 8 : 0)
        .padding(.vertical, supportsLiquidGlassChrome ? 6 : 0)
        .background(composerDockBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func sendDraftIfPossible() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        ResolveKitChatViewLogger.log(
            "sendDraftIfPossible draft_len=\(draft.count) trimmed_len=\(trimmed.count) turn_in_progress=\(runtime.isTurnInProgress) state=\(runtime.connectionState.rawValue)"
        )
        guard !trimmed.isEmpty else {
            ResolveKitChatViewLogger.log("sendDraftIfPossible blocked empty draft")
            return
        }
        guard !runtime.isTurnInProgress else {
            ResolveKitChatViewLogger.log("sendDraftIfPossible blocked turn already in progress")
            return
        }
        dismissComposerIfNeeded()
        draft = ""
        ResolveKitChatViewLogger.log("sendDraftIfPossible dispatching runtime.sendMessage")
        Task { await runtime.sendMessage(trimmed) }
    }

    @discardableResult
    private func dismissComposerIfNeeded() -> Bool {
        composerFocusState.isFocused = isComposerFocused
        guard composerFocusState.dismiss() else { return false }
        isComposerFocused = composerFocusState.isFocused
        return true
    }

    private func copyToClipboard(_ text: String) {
        #if os(iOS)
        UIPasteboard.general.string = text
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }

    private var preferredColorScheme: ColorScheme? {
        switch runtime.appearanceMode {
        case .system:
            return nil
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }

    private var resolvedPalette: ResolveKitChatPalette {
        switch runtime.appearanceMode {
        case .light:
            return runtime.chatTheme.light
        case .dark:
            return runtime.chatTheme.dark
        case .system:
            return systemColorScheme == .dark ? runtime.chatTheme.dark : runtime.chatTheme.light
        }
    }

    private var supportsLiquidGlassChrome: Bool {
        #if os(iOS)
        if #available(iOS 26, *) { return true }
        return false
        #elseif os(macOS)
        if #available(macOS 26, *) { return true }
        return false
        #else
        return false
        #endif
    }

    @ViewBuilder
    private func composerFieldBackground(isLoading: Bool) -> some View {
        if supportsLiquidGlassChrome {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
        } else {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(
                    isLoading
                        ? resolvedPalette.composerBackgroundColor.opacity(0.55)
                        : resolvedPalette.composerBackgroundColor
                )
        }
    }

    @ViewBuilder
    private func composerFieldBorder(isLoading: Bool) -> some View {
        let color: Color = supportsLiquidGlassChrome
            ? Color.white.opacity(0.22)
            : (isLoading ? resolvedPalette.toolCardBorderColor.opacity(0.45) : resolvedPalette.toolCardBorderColor)

        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(color, lineWidth: 1)
    }

    @ViewBuilder
    private var composerSendButtonBackground: some View {
        if supportsLiquidGlassChrome {
            Capsule()
                .fill(.ultraThinMaterial)
        } else {
            Color.clear
        }
    }

    @ViewBuilder
    private var composerSendButtonBorder: some View {
        if supportsLiquidGlassChrome {
            Capsule()
                .stroke(Color.white.opacity(0.22), lineWidth: 1)
        }
    }

    @ViewBuilder
    private var composerDockBackground: some View {
        if supportsLiquidGlassChrome {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.clear)
        } else {
            Color.clear
        }
    }
}

private enum ResolveKitChatScrollPinning {
    static func isNearBottom(anchorMaxY: CGFloat, viewportHeight: CGFloat, tolerance: CGFloat = 24) -> Bool {
        guard anchorMaxY.isFinite, viewportHeight.isFinite else { return true }
        return anchorMaxY <= viewportHeight + tolerance
    }
}

private enum ResolveKitForceScrollToBottomNotification {
    static let name = Notification.Name("ResolveKitForceScrollToBottomNotification")
}

private struct ResolveKitBottomAnchorMaxYPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = .infinity

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct ResolveKitComposerHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private extension View {
    @ViewBuilder
    func resolveKitScrollDismissesKeyboard() -> some View {
        #if os(iOS)
        if #available(iOS 16, *) {
            switch ResolveKitScrollKeyboardDismissBehavior.current {
            case .interactive:
                self.scrollDismissesKeyboard(.interactively)
            }
        } else {
            self
        }
        #else
        self
        #endif
    }
}

private struct TypingIndicatorBubble: View {
    let palette: ResolveKitChatPalette
    private let ticker = Timer.publish(every: 0.32, on: .main, in: .common).autoconnect()
    @State private var activeDot = 0

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            HStack(spacing: 6) {
                dot(index: 0)
                dot(index: 1)
                dot(index: 2)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(palette.loaderBubbleBackgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 15))

            Circle()
                .fill(palette.loaderBubbleBackgroundColor)
                .frame(width: 8, height: 8)
                .offset(x: 2, y: 6)
        }
        .onReceive(ticker) { _ in
            activeDot = (activeDot + 1) % 3
        }
    }

    private func dot(index: Int) -> some View {
        let isActive = activeDot % 3 == index
        return Circle()
            .fill(isActive ? palette.loaderDotActiveColor : palette.loaderDotInactiveColor)
            .frame(width: 7, height: 7)
            .scaleEffect(isActive ? 1.0 : 0.86)
            .animation(.easeInOut(duration: 0.25), value: activeDot)
    }
}
