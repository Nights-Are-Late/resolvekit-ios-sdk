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

public struct ResolveKitChatView: View {
    private struct ScrollTrigger: Hashable {
        let messageCount: Int
        let lastMessageID: UUID?
        let toolBatchCount: Int
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
    @ObservedObject private var runtime: ResolveKitRuntime
    @Environment(\.colorScheme) private var systemColorScheme
    @State private var draft = ""
    @State private var showThinkingIndicator = false
    @State private var thinkingDelayTask: Task<Void, Never>?
    @Namespace private var bubbleMorphNamespace

    public init(runtime: ResolveKitRuntime) {
        self.runtime = runtime
    }

    public var body: some View {
        GeometryReader { geometry in
            let safeAreaTop = geometry.safeAreaInsets.top
            let contentTopInset = topContentInset(safeAreaTop: safeAreaTop)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(timelineEntries) { entry in
                            switch entry {
                            case .message(let message):
                                messageRow(message)
                                    .transition(
                                        .asymmetric(
                                            insertion: .scale(scale: 0.92).combined(with: .opacity),
                                            removal: .opacity
                                        )
                                    )
                            case .toolBatch(let batch):
                                toolBatchRow(batch)
                                    .transition(
                                        .asymmetric(
                                            insertion: .scale(scale: 0.92).combined(with: .opacity),
                                            removal: .opacity
                                        )
                                    )
                            }
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
                        Color.clear
                            .frame(height: 24)
                            .id(bottomAnchorID)
                    }
                    .padding(.leading, 16)
                    .padding(.trailing, 16)
                    .padding(.top, contentTopInset)
                    .padding(.bottom, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .ignoresSafeArea(edges: .top)
                .safeAreaInset(edge: .bottom) {
                    composer
                        .padding(.horizontal)
                        .padding(.top, 8)
                        .padding(.bottom, 4)
                        .background(.clear)
                }
                .task(id: scrollTrigger) {
                    await MainActor.run {
                        withAnimation(scrollSpring) {
                            proxy.scrollTo(bottomAnchorID, anchor: .bottom)
                        }
                    }
                    await ResolveKitCompatibility.sleep(milliseconds: 70)
                    await MainActor.run {
                        withAnimation(scrollSpring) {
                            proxy.scrollTo(bottomAnchorID, anchor: .bottom)
                        }
                    }
                }
                .onChange(of: showThinkingIndicator) { isVisible in
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
                        proxy.scrollTo(bottomAnchorID, anchor: .bottom)
                    }
                }
                .task {
                    await MainActor.run {
                        proxy.scrollTo(bottomAnchorID, anchor: .bottom)
                    }
                }
            }
            .background(resolvedPalette.screenBackgroundColor)
            .preferredColorScheme(preferredColorScheme)
            .navigationTitle(runtime.chatTitle)
            .resolveKitInlineTransparentNavigationBar()
            .overlay(alignment: .top) {
                topNavigationFade(height: topFadeHeight(safeAreaTop: safeAreaTop))
            }
        }
        .task {
            do {
                try await runtime.start()
            } catch {
                // Runtime already updates published error state.
            }
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    Task { await runtime.reloadWithNewSession() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel("Reload chat")
                .help("Start a new chat session")
            }
        }
        .onChange(of: isThinkingVisibleRaw) { isVisible in
            if !isVisible {
                thinkingDelayTask?.cancel()
                thinkingDelayTask = nil
                withAnimation(.easeOut(duration: 0.18)) {
                    showThinkingIndicator = false
                }
                return
            }

            thinkingDelayTask?.cancel()
            thinkingDelayTask = Task { @MainActor in
                await ResolveKitCompatibility.sleep(milliseconds: 500)
                guard !Task.isCancelled, isThinkingVisibleRaw else { return }
                withAnimation(.spring(response: 0.38, dampingFraction: 0.72, blendDuration: 0.12)) {
                    showThinkingIndicator = true
                }
            }
        }
        .onDisappear {
            thinkingDelayTask?.cancel()
            thinkingDelayTask = nil
        }
        .animation(
            .spring(response: 0.38, dampingFraction: 0.72, blendDuration: 0.12),
            value: runtime.messages.map { $0.id.uuidString } + runtime.toolCallBatches.map { $0.id.uuidString }
        )
    }

    private var isThinkingVisibleRaw: Bool {
        runtime.isTurnInProgress && runtime.toolCallChecklist.isEmpty
    }

    private var shouldShowThinkingIndicator: Bool {
        showThinkingIndicator && morphTargetAssistantID == nil
    }

    private var morphTargetAssistantID: UUID? {
        guard showThinkingIndicator else { return nil }
        guard let last = runtime.messages.last, last.role == .assistant else { return nil }
        return last.id
    }

    private var scrollTrigger: ScrollTrigger {
        ScrollTrigger(
            messageCount: runtime.messages.count,
            lastMessageID: runtime.messages.last?.id,
            toolBatchCount: runtime.toolCallBatches.count
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
        runtime.isTurnInProgress
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
        draft = ""
        ResolveKitChatViewLogger.log("sendDraftIfPossible dispatching runtime.sendMessage")
        Task { await runtime.sendMessage(trimmed) }
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

private extension View {
    @ViewBuilder
    func resolveKitInlineTransparentNavigationBar() -> some View {
        #if os(iOS)
        self
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
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
