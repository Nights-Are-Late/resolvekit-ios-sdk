# ResolveKit iOS Sample App

Demo structure:

1. **Configuration screen** (host + API key required)
2. **Capabilities screen** (supported functions, test instructions, and `Open Chat` CTA)

After you run tool calls in chat, dismiss chat and return to the capabilities screen to verify that app state changed.

## Run locally

```bash
cd sample/ResolveKitSample
xcodegen generate
open ResolveKitSample.xcodeproj
```

Then run the `ResolveKitSample` scheme on an iOS Simulator.

## Tool calls showcased

- `set_demo_vibe`
- `launch_confetti`
- `rename_mascot`
- `arm_lasers` (approval required)
- `get_showcase_state`
- `echo_message` (macro-generated function)
