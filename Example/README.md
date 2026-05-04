# ResolveKit Demo App

A minimal iOS app demonstrating the ResolveKit SDK integration. This example covers:

- **SDK initialization** with `ResolveKitRuntime` and `ResolveKitConfiguration`
- **Chat UI embedding** via `ResolveKitChatView` in SwiftUI
- **Function definitions** using the `@ResolveKit` macro
- **Approval flow** — functions with `requiresApproval: true` trigger the built-in approval UI
- **Connection state observation** — live banner showing stream lifecycle

## Project Structure

```
Example/ResolveKitDemo/
├── Package.swift                          # SPM manifest (depends on parent SDK)
├── README.md                              # This file
└── Sources/ResolveKitDemo/
    ├── ResolveKitDemoApp.swift            # App entry point
    ├── Functions/
    │   ├── GetLocalTime.swift             # Read-only function (auto-executes)
    │   ├── SendReminder.swift             # Parameterized function (requires approval)
    │   └── GetDeviceStatus.swift          # Device info function (requires approval)
    └── Views/
        └── ContentView.swift              # Main chat view + connection state banner
```

## Requirements

- Xcode 15.0+
- iOS 16.0+ device or simulator
- A running ResolveKit backend with a valid API key

## Setup

### 1. Clone the SDK (if not already present)

```bash
git clone https://github.com/resolve-kit/resolvekit-ios-sdk.git
cd resolvekit-ios-sdk
```

### 2. Set your API key

The demo reads the API key from the `RESOLVEKIT_API_KEY` environment variable. Set it before building:

```bash
export RESOLVEKIT_API_KEY="rk_your_dev_key"
```

Alternatively, edit the `apiKeyProvider` closure in `ContentView.swift` to return your key directly (for local testing only — never commit real keys).

### 3. Build and Run

#### Option A: Command line (Swift Package Manager)

```bash
cd Example/ResolveKitDemo
swift build
```

#### Option B: Xcode (recommended)

Generate an Xcode project and open it:

```bash
cd Example/ResolveKitDemo
swift package generate-xcodeproj
open ResolveKitDemo.xcodeproj
```

Then select an iOS simulator or device and press **Run** (⌘R).

### 4. Test the demo

Once the app launches, you'll see the ResolveKit chat interface:

1. **Send a message** like _"What time is it?"_ — the LLM will call `GetLocalTime` automatically (no approval needed since `requiresApproval: false`).

2. **Ask it to set a reminder** like _"Remind me to drink water in 30 minutes"_ — the approval UI will appear showing `SendReminder` with its parameters. Tap **Approve All** to execute.

3. **Ask about your device** like _"What device am I using?"_ — `GetDeviceStatus` will appear in the approval UI with device details pending confirmation.

4. **Watch the connection state banner** at the bottom during startup and if the network drops.

## Key Integration Points

### SDK Initialization

```swift
@StateObject private var runtime = ResolveKitRuntime(configuration: ResolveKitConfiguration(
    apiKeyProvider: { "rk_your_api_key" },
    functions: [GetLocalTime.self, SendReminder.self, GetDeviceStatus.self]
))
```

### Chat UI

```swift
ResolveKitChatView(runtime: runtime)
```

### Function Definition (macro pattern)

```swift
@ResolveKit(name: "get_local_time", description: "...", requiresApproval: false)
struct GetLocalTime: ResolveKitFunction {
    func perform() async throws -> String {
        return Date().description
    }
}
```

### Function Definition (manual pattern)

For custom schemas or dynamic dispatch, conform to `AnyResolveKitFunction` directly. See the [main README](../../README.md#pattern-b-manual-conformance-anyresolvekitfunction) for details.

## Troubleshooting

| Issue | Fix |
|-------|-----|
| `Missing API key` | Ensure `apiKeyProvider` returns a non-empty string. Check `RESOLVEKIT_API_KEY` env var. |
| Chat stuck in `blocked` | SDK version is incompatible with backend. Update the SDK to the latest version. |
| Functions not appearing | Verify function types are listed in `ResolveKitConfiguration.functions`. |
| Approval UI doesn't show | Check that `requiresApproval: true` is set on the `@ResolveKit` macro for that function. |

## License

MIT — same as the parent SDK.
