import SwiftUI
import ResolveKitUI

/// Main content view demonstrating the full ResolveKit integration.
/// Shows SDK initialization, chat UI embedding, and runtime state observation.
struct ContentView: View {
    // MARK: - Runtime

    @StateObject private var runtime = ResolveKitRuntime(configuration: ResolveKitConfiguration(
        // In a real app, load this from Keychain or a secure config source.
        apiKeyProvider: {
            ProcessInfo.processInfo.environment["RESOLVEKIT_API_KEY"]
                ?? "rk_your_api_key_here"
        },
        // Register all demo functions — the LLM can call any of these.
        functions: [
            GetLocalTime.self,     // Auto-executes (no approval needed)
            SendReminder.self,     // Requires user approval
            GetDeviceStatus.self   // Requires user approval
        ],
        // Pass device context to the backend for smarter routing.
        llmContextProvider: {
            [
                "platform": .string("ios"),
                "demo_mode": .bool(true)
            ]
        }
    ))

    // MARK: - Body

    var body: some View {
        ResolveKitChatView(runtime: runtime)
            .overlay(alignment: .bottom) {
                // Simple connection state indicator.
                ConnectionStateBanner(state: runtime.connectionState)
            }
    }
}

// MARK: - Connection State Banner

/// A lightweight banner showing the current connection state.
/// Appears at the bottom of the chat view.
struct ConnectionStateBanner: View {
    let state: ResolveKitConnectionState

    private var label: String {
        switch state {
        case .idle:
            return "Idle"
        case .registering:
            return "Registering functions…"
        case .connecting:
            return "Connecting…"
        case .active:
            return ""
        case .reconnecting:
            return "Reconnecting…"
        case .reconnected:
            return "Reconnected"
        case .failed:
            return "Connection failed"
        case .blocked:
            return "Blocked — check API key"
        @unknown default:
            return "Unknown state"
        }
    }

    private var color: Color {
        switch state {
        case .active, .reconnected:
            return .clear
        case .registering, .connecting:
            return .orange
        case .reconnecting:
            return .yellow
        case .failed, .blocked:
            return .red
        case .idle:
            return .gray
        @unknown default:
            return .gray
        }
    }

    var body: some View {
        if !label.isEmpty {
            Text(label)
                .font(.caption2)
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(color, in: Capsule())
                .padding(.bottom, 8)
        }
    }
}

// MARK: - Preview

#Preview {
    ContentView()
}
