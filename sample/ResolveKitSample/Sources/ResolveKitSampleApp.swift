import SwiftUI
import ResolveKitUI
import ResolveKitCore
import ResolveKitAuthoring

private let managedHostURL = "https://agent.resolvekit.app"

struct SampleConnectionSettings: Equatable, Sendable {
    var hostURL: String
    var apiKey: String

    static let `default` = SampleConnectionSettings(hostURL: managedHostURL, apiKey: "")

    var normalizedHostURL: String {
        let trimmed = hostURL.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? managedHostURL : trimmed
    }

    var normalizedAPIKey: String {
        apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var canContinue: Bool {
        URL(string: normalizedHostURL) != nil && !normalizedAPIKey.isEmpty
    }

    var maskedAPIKey: String {
        let key = normalizedAPIKey
        if key.isEmpty { return "(not set)" }
        guard key.count > 8 else { return "****" }
        return "\(key.prefix(4))...\(key.suffix(4))"
    }
}

enum SampleSettingsStore {
    private static let hostKey = "resolvekit.sample.host"
    private static let apiKeyKey = "resolvekit.sample.api_key"

    static func load() -> SampleConnectionSettings {
        let defaults = UserDefaults.standard
        let host = defaults.string(forKey: hostKey) ?? managedHostURL
        let apiKey = defaults.string(forKey: apiKeyKey) ?? ""
        return SampleConnectionSettings(hostURL: host, apiKey: apiKey)
    }

    static func save(_ settings: SampleConnectionSettings) {
        let defaults = UserDefaults.standard
        defaults.set(settings.normalizedHostURL, forKey: hostKey)
        defaults.set(settings.normalizedAPIKey, forKey: apiKeyKey)
    }
}

struct DemoAppState: Sendable, Equatable {
    var vibe: String = "Chill"
    var accent: String = "Cyan"
    var mascot: String = "Robo Otter"
    var confettiBursts: Int = 0
    var lasersArmed: Bool = false

    var asJSON: JSONValue {
        .object([
            "vibe": .string(vibe),
            "accent": .string(accent),
            "mascot": .string(mascot),
            "confetti_bursts": .number(Double(confettiBursts)),
            "lasers_armed": .bool(lasersArmed)
        ])
    }
}

@MainActor
final class SampleShowcaseState: ObservableObject {
    static let shared = SampleShowcaseState()

    @Published private(set) var state = DemoAppState()

    func setVibe(_ input: String) -> DemoAppState {
        let normalized = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch normalized {
        case "neon", "cyber", "party":
            state.vibe = "Neon Surge"
            state.accent = "Electric Pink"
        case "chaos", "wild", "rad":
            state.vibe = "Chaos Mode"
            state.accent = "Lime"
        default:
            state.vibe = "Chill"
            state.accent = "Cyan"
        }
        return state
    }

    func launchConfetti(power: Int) -> DemoAppState {
        let bursts = min(max(power, 1), 20)
        state.confettiBursts += bursts
        return state
    }

    func renameMascot(_ name: String) -> DemoAppState {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        state.mascot = trimmed.isEmpty ? "Robo Otter" : trimmed
        return state
    }

    func armLasers(_ enabled: Bool) -> DemoAppState {
        state.lasersArmed = enabled
        return state
    }

    func snapshot() -> DemoAppState {
        state
    }
}

@ResolveKit(name: "echo_message", description: "Returns the same message back to the user", requiresApproval: false)
struct EchoMessage: ResolveKitFunction {
    func perform(message: String) async throws -> String {
        message
    }
}

enum SetDemoVibe: AnyResolveKitFunction {
    static let resolveKitName = "set_demo_vibe"
    static let resolveKitDescription = "Sets app vibe preset: chill, neon, or chaos"
    static let resolveKitTimeoutSeconds: Int? = 5
    static let resolveKitRequiresApproval = false
    static let resolveKitParametersSchema: JSONObject = [
        "type": .string("object"),
        "properties": .object([
            "vibe": .object(["type": .string("string")])
        ]),
        "required": .array([.string("vibe")])
    ]

    static func invoke(arguments: JSONObject, context: ResolveKitFunctionContext) async throws -> JSONValue {
        let vibe = arguments["vibe"].flatMap(TypeResolver.coerceString) ?? "chill"
        let next = await MainActor.run { SampleShowcaseState.shared.setVibe(vibe) }
        return next.asJSON
    }
}

enum LaunchConfetti: AnyResolveKitFunction {
    static let resolveKitName = "launch_confetti"
    static let resolveKitDescription = "Adds confetti bursts to the demo counter"
    static let resolveKitTimeoutSeconds: Int? = 5
    static let resolveKitRequiresApproval = false
    static let resolveKitParametersSchema: JSONObject = [
        "type": .string("object"),
        "properties": .object([
            "power": .object(["type": .string("integer")])
        ]),
        "required": .array([.string("power")])
    ]

    static func invoke(arguments: JSONObject, context: ResolveKitFunctionContext) async throws -> JSONValue {
        let power = arguments["power"].flatMap(TypeResolver.coerceInt) ?? 1
        let next = await MainActor.run { SampleShowcaseState.shared.launchConfetti(power: power) }
        return next.asJSON
    }
}

enum RenameMascot: AnyResolveKitFunction {
    static let resolveKitName = "rename_mascot"
    static let resolveKitDescription = "Renames the demo mascot shown in the app"
    static let resolveKitTimeoutSeconds: Int? = 5
    static let resolveKitRequiresApproval = false
    static let resolveKitParametersSchema: JSONObject = [
        "type": .string("object"),
        "properties": .object([
            "name": .object(["type": .string("string")])
        ]),
        "required": .array([.string("name")])
    ]

    static func invoke(arguments: JSONObject, context: ResolveKitFunctionContext) async throws -> JSONValue {
        let name = arguments["name"].flatMap(TypeResolver.coerceString) ?? "Robo Otter"
        let next = await MainActor.run { SampleShowcaseState.shared.renameMascot(name) }
        return next.asJSON
    }
}

enum ArmLasers: AnyResolveKitFunction {
    static let resolveKitName = "arm_lasers"
    static let resolveKitDescription = "Arms or disarms demo lasers; requires approval"
    static let resolveKitTimeoutSeconds: Int? = 10
    static let resolveKitRequiresApproval = true
    static let resolveKitParametersSchema: JSONObject = [
        "type": .string("object"),
        "properties": .object([
            "enabled": .object(["type": .string("boolean")])
        ]),
        "required": .array([.string("enabled")])
    ]

    static func invoke(arguments: JSONObject, context: ResolveKitFunctionContext) async throws -> JSONValue {
        let enabled = arguments["enabled"].flatMap(TypeResolver.coerceBool) ?? false
        let next = await MainActor.run { SampleShowcaseState.shared.armLasers(enabled) }
        return next.asJSON
    }
}

enum GetShowcaseState: AnyResolveKitFunction {
    static let resolveKitName = "get_showcase_state"
    static let resolveKitDescription = "Returns current demo app state"
    static let resolveKitTimeoutSeconds: Int? = 5
    static let resolveKitRequiresApproval = false
    static let resolveKitParametersSchema: JSONObject = [
        "type": .string("object"),
        "properties": .object([:])
    ]

    static func invoke(arguments: JSONObject, context: ResolveKitFunctionContext) async throws -> JSONValue {
        let snapshot = await MainActor.run { SampleShowcaseState.shared.snapshot() }
        return snapshot.asJSON
    }
}

enum SampleDemoFunctionPack: ResolveKitFunctionPack {
    static let packName = "sample_demo_tools"
    static let supportedPlatforms: [ResolveKitPlatform] = [.ios]
    static let functions: [any AnyResolveKitFunction.Type] = [
        SetDemoVibe.self,
        LaunchConfetti.self,
        RenameMascot.self,
        ArmLasers.self,
        GetShowcaseState.self,
        EchoMessage.self
    ]
}

enum SampleRuntimeFactory {
    static let availableFunctionNames = [
        "set_demo_vibe",
        "launch_confetti",
        "rename_mascot",
        "arm_lasers",
        "get_showcase_state",
        "echo_message"
    ]

    @MainActor
    static func makeRuntime(settings: SampleConnectionSettings) -> ResolveKitRuntime {
        let baseURL = URL(string: settings.normalizedHostURL) ?? URL(string: managedHostURL)!
        let apiKey = settings.normalizedAPIKey

        let configuration = ResolveKitConfiguration(
            baseURL: baseURL,
            apiKeyProvider: { apiKey.isEmpty ? nil : apiKey },
            llmContextProvider: {
                [
                    "app_name": .string("ResolveKit iOS Sample"),
                    "demo_goal": .string("Call tools to change visible app state")
                ]
            },
            availableFunctionNamesProvider: { availableFunctionNames },
            functionPacks: [SampleDemoFunctionPack.self]
        )
        return ResolveKitRuntime(configuration: configuration)
    }
}

struct ToolGuide: Identifiable {
    let id = UUID()
    let functionName: String
    let prompt: String
    let expected: String
}

private let toolGuides: [ToolGuide] = [
    .init(functionName: "set_demo_vibe", prompt: "Set the demo vibe to neon.", expected: "Vibe and accent update on screen."),
    .init(functionName: "launch_confetti", prompt: "Launch confetti with power 7.", expected: "Confetti burst counter increases."),
    .init(functionName: "rename_mascot", prompt: "Rename mascot to Laser Panda.", expected: "Mascot name changes on screen."),
    .init(functionName: "arm_lasers (approval required)", prompt: "Arm lasers.", expected: "Approval appears, then laser state flips."),
    .init(functionName: "get_showcase_state", prompt: "Show current showcase state.", expected: "Assistant returns vibe/mascot/confetti/laser values."),
    .init(functionName: "echo_message (macro)", prompt: "Echo this exactly: ResolveKit is rad.", expected: "Assistant returns the same text.")
]

enum SampleStep {
    case configuration
    case capabilities
}

@main
struct ResolveKitSampleApp: App {
    @State private var step: SampleStep = .configuration
    @State private var settings = SampleSettingsStore.load()

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                switch step {
                case .configuration:
                    ConfigurationScreen(
                        settings: settings,
                        onChange: { settings = $0 },
                        onContinue: {
                            SampleSettingsStore.save(settings)
                            step = .capabilities
                        }
                    )
                case .capabilities:
                    CapabilitiesScreen(
                        settings: settings,
                        onBack: { step = .configuration }
                    )
                }
            }
        }
    }
}

struct ConfigurationScreen: View {
    let settings: SampleConnectionSettings
    let onChange: (SampleConnectionSettings) -> Void
    let onContinue: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Step 1 of 2: Configuration")
                    .font(.title2.bold())

                VStack(alignment: .leading, spacing: 10) {
                    Text("Connect sample app")
                        .font(.headline)
                    Text("You must provide host and API key before continuing.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    TextField("https://agent.resolvekit.app", text: Binding(
                        get: { settings.hostURL },
                        set: { onChange(.init(hostURL: $0, apiKey: settings.apiKey)) }
                    ))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .textFieldStyle(.roundedBorder)

                    SecureField("rk_...", text: Binding(
                        get: { settings.apiKey },
                        set: { onChange(.init(hostURL: settings.hostURL, apiKey: $0)) }
                    ))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)

                    Button("Use Managed Host") {
                        onChange(.init(hostURL: managedHostURL, apiKey: settings.apiKey))
                    }

                    if !settings.canContinue {
                        Text("Configuration incomplete: host and API key are required.")
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }

                    Button("Continue") {
                        onContinue()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!settings.canContinue)
                }
                .padding()
                .background(.thinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding()
        }
        .navigationTitle("ResolveKit Sample")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct CapabilitiesScreen: View {
    let settings: SampleConnectionSettings
    let onBack: () -> Void
    @State private var showChat = false
    @StateObject private var showcase = SampleShowcaseState.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Step 2 of 2: Capabilities")
                    .font(.title2.bold())

                infoCard
                stateCard
                functionsCard
                instructionsCard
            }
            .padding()
        }
        .navigationTitle("Capabilities")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Back") { onBack() }
            }
        }
        .sheet(isPresented: $showChat) {
            ChatHostScreen(settings: settings)
        }
    }

    private var infoCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Connected settings").font(.headline)
            Text("Host: \(settings.normalizedHostURL)")
            Text("API key: \(settings.maskedAPIKey)")
        }
        .font(.footnote)
        .padding()
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var stateCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Live App State (changed by tool calls)").font(.headline)
            Text("Vibe: \(showcase.state.vibe)")
            Text("Accent: \(showcase.state.accent)")
            Text("Mascot: \(showcase.state.mascot)")
            Text("Confetti bursts: \(showcase.state.confettiBursts)")
            Text("Lasers armed: \(showcase.state.lasersArmed ? "true" : "false")")
        }
        .font(.footnote)
        .padding()
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var functionsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Supported Functions").font(.headline)
            ForEach(toolGuides) { guide in
                VStack(alignment: .leading, spacing: 2) {
                    Text(guide.functionName).font(.subheadline.bold())
                    Text("Try: \"\(guide.prompt)\"")
                    Text("Expected: \(guide.expected)")
                }
                .font(.footnote)
            }
        }
        .padding()
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var instructionsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("How To Test").font(.headline)
            Text("1. Tap Open Chat.")
                .font(.footnote)
            Text("2. Send prompts from Supported Functions.")
                .font(.footnote)
            Text("3. Dismiss chat and verify Live App State changed.")
                .font(.footnote)

            Button("Open Chat") {
                showChat = true
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

struct ChatHostScreen: View {
    let settings: SampleConnectionSettings
    @Environment(\.dismiss) private var dismiss
    @StateObject private var runtime: ResolveKitRuntime

    @MainActor
    init(settings: SampleConnectionSettings) {
        self.settings = settings
        _runtime = StateObject(wrappedValue: SampleRuntimeFactory.makeRuntime(settings: settings))
    }

    var body: some View {
        NavigationStack {
            ResolveKitChatView(runtime: runtime)
                .navigationTitle("ResolveKit Chat")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { dismiss() }
                    }
                }
        }
    }
}
