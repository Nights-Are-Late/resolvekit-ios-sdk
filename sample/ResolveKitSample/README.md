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

## Build a DMG (Apple Silicon Mac)

This sample is an iOS app with Mac Catalyst enabled. The DMG packaging path
builds the Mac Catalyst app bundle and wraps it in a disk image.

```bash
cd sample/ResolveKitSample
./build_dmg.sh
```

Output:

- DMG: `sample/ResolveKitSample/build/artifacts/ResolveKitSample-release.dmg`
- App bundle: built under `sample/ResolveKitSample/build/DerivedData-dmg/Build/Products/Release-maccatalyst/`
- Architectures: `arm64` + `x86_64` (universal Mac app)

Optional overrides:

```bash
DESTINATION_ID=<mac_destination_id> \
CONFIGURATION=Release \
DMG_PATH=./build/artifacts/custom-name.dmg \
./build_dmg.sh
```

## Tool calls showcased

- `set_demo_vibe`
- `launch_confetti`
- `rename_mascot`
- `arm_lasers` (approval required)
- `get_showcase_state`
- `echo_message` (macro-generated function)
