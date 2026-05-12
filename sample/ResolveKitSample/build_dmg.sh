#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SAMPLE_DIR="$SCRIPT_DIR"
PROJECT_FILE="$SAMPLE_DIR/ResolveKitSample.xcodeproj"
PROJECT_YML="$SAMPLE_DIR/project.yml"
SCHEME="ResolveKitSample"
CONFIGURATION="${CONFIGURATION:-Release}"
OUTPUT_DIR="${OUTPUT_DIR:-$SAMPLE_DIR/build/artifacts}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$SAMPLE_DIR/build/DerivedData-dmg}"
VOLUME_NAME="${VOLUME_NAME:-ResolveKitSample}"
DEVELOPMENT_TEAM="${DEVELOPMENT_TEAM:-}"
APP_ARCHS="${APP_ARCHS:-arm64 x86_64}"

config_lowercase="$(printf '%s' "$CONFIGURATION" | tr '[:upper:]' '[:lower:]')"
DMG_PATH="${DMG_PATH:-$OUTPUT_DIR/ResolveKitSample-${config_lowercase}.dmg}"

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "error: xcodegen is required. Install via: brew install xcodegen" >&2
  exit 1
fi

if [ ! -f "$PROJECT_YML" ]; then
  echo "error: missing project.yml at $PROJECT_YML" >&2
  exit 1
fi

if [ ! -f "$PROJECT_FILE/project.pbxproj" ]; then
  echo "info: generating Xcode project with xcodegen"
fi

(
  cd "$SAMPLE_DIR"
  xcodegen generate >/dev/null
)

DESTINATION_ID="${DESTINATION_ID:-}"
if [ -z "$DESTINATION_ID" ]; then
  DESTINATION_ID="$(
    xcodebuild -project "$PROJECT_FILE" -scheme "$SCHEME" -showdestinations 2>/dev/null \
      | sed -n 's/.*platform:macOS, arch:[^,]*, variant:Mac Catalyst, id:\([^,}]*\).*/\1/p' \
      | head -n 1
  )"
fi

if [ -z "$DESTINATION_ID" ]; then
  echo "error: could not find a macOS destination with variant Mac Catalyst." >&2
  echo "hint: enable Mac Catalyst in the target settings or pass DESTINATION_ID=<id>." >&2
  exit 1
fi

echo "Using destination id: $DESTINATION_ID"
mkdir -p "$OUTPUT_DIR"
rm -rf "$DERIVED_DATA_PATH"

XCODEBUILD_ARGS=(
  -project "$PROJECT_FILE"
  -scheme "$SCHEME"
  -configuration "$CONFIGURATION"
  -destination "id=$DESTINATION_ID,variant=Mac Catalyst"
  -derivedDataPath "$DERIVED_DATA_PATH"
  "ARCHS=$APP_ARCHS"
  ONLY_ACTIVE_ARCH=NO
  build
)

if [ -n "$DEVELOPMENT_TEAM" ]; then
  XCODEBUILD_ARGS+=("DEVELOPMENT_TEAM=$DEVELOPMENT_TEAM")
  echo "Using DEVELOPMENT_TEAM=$DEVELOPMENT_TEAM for signed build."
else
  XCODEBUILD_ARGS+=(CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO)
  echo "No DEVELOPMENT_TEAM provided. Building unsigned app."
fi

xcodebuild "${XCODEBUILD_ARGS[@]}"

APP_PATH="$(find "$DERIVED_DATA_PATH/Build/Products" -maxdepth 3 -type d -name "ResolveKitSample.app" | head -n 1)"
if [ -z "$APP_PATH" ]; then
  echo "error: built app bundle not found under $DERIVED_DATA_PATH/Build/Products" >&2
  exit 1
fi

if [[ "$APP_PATH" != *"Release-maccatalyst"* ]]; then
  echo "error: expected a Mac Catalyst app but found: $APP_PATH" >&2
  exit 1
fi

STAGING_DIR="$(mktemp -d "$SAMPLE_DIR/build/dmg-stage.XXXXXX")"
cleanup() {
  rm -rf "$STAGING_DIR"
}
trap cleanup EXIT

cp -R "$APP_PATH" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

# Ensure the copied app has a valid local signature when built without a team.
codesign --force --deep --sign - "$STAGING_DIR/ResolveKitSample.app" >/dev/null

rm -f "$DMG_PATH"
hdiutil create \
  -volname "$VOLUME_NAME" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH" >/dev/null

echo "DMG created: $DMG_PATH"
echo "App inside DMG: $(basename "$APP_PATH")"
