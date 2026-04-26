#!/usr/bin/env bash
set -euo pipefail

# iOS CLI helper
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
IOS_DIR="$ROOT_DIR/ios"
PROJECT="$IOS_DIR/NuruNuru.xcodeproj"
SCHEME="NuruNuru"
CONFIG="Debug"
APP_BUNDLE_ID="io.nurunuru.app"
DERIVED="$IOS_DIR/build-cli"
SIM_DEFAULT_ID="CD2FD68F-076A-4A91-ADF8-A2828AC38A95"
DEVICE_DEFAULT_ID="00008101-000D148A0E82001E"

cmd="${1:-}"
case "$cmd" in
  device|device-run)
    DEVICE_ID="${2:-$DEVICE_DEFAULT_ID}"
    echo "[1/4] Build for device: $DEVICE_ID"
    xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration "$CONFIG" \
      -destination "id=$DEVICE_ID" \
      -derivedDataPath "$DERIVED" \
      -allowProvisioningUpdates \
      build
    APP_PATH="$DERIVED/Build/Products/$CONFIG-iphoneos/NuruNuru.app"
    [[ -d "$APP_PATH" ]] || { echo "Device app not found: $APP_PATH" >&2; exit 1; }
    echo "[2/4] Install app"
    xcrun devicectl device install app --device "$DEVICE_ID" "$APP_PATH"
    echo "[3/4] Launch app"
    xcrun devicectl device process launch --device "$DEVICE_ID" "$APP_BUNDLE_ID" --activate
    echo "[4/4] Process check"
    xcrun devicectl device info processes --device "$DEVICE_ID" | grep -E "$APP_BUNDLE_ID|NuruNuru" || true
    ;;
  proc)
    DEVICE_ID="${2:-$DEVICE_DEFAULT_ID}"
    xcrun devicectl device info processes --device "$DEVICE_ID" | grep -E "$APP_BUNDLE_ID|NuruNuru" || true
    ;;
  logs-device)
    DEVICE_ID="${2:-$DEVICE_DEFAULT_ID}"
    xcrun devicectl device process launch --device "$DEVICE_ID" "$APP_BUNDLE_ID" --console --activate
    ;;
  diagnose-device)
    DEVICE_ID="${2:-$DEVICE_DEFAULT_ID}"
    TS="$(date +%Y%m%d-%H%M%S)"
    OUT_ZIP="$DERIVED/devicectl-diagnose-$TS.zip"
    OUT_JSON="$DERIVED/devicectl-diagnose-$TS.json"
    OUT_LOG="$DERIVED/devicectl-diagnose-$TS.log"
    mkdir -p "$DERIVED"
    echo "Collecting diagnostics for device: $DEVICE_ID"
    echo "Archive: $OUT_ZIP"
    xcrun devicectl diagnose \
      --devices "$DEVICE_ID" \
      --no-finder \
      --timeout 300 \
      --archive-destination "$OUT_ZIP" \
      --json-output "$OUT_JSON" \
      --log-output "$OUT_LOG" || true
    echo "Done. Check files under: $DERIVED"
    ;;
  *)
    echo "Usage: $0 device-run [DEVICE_ID] | proc [DEVICE_ID] | logs-device [DEVICE_ID] | diagnose-device [DEVICE_ID]"
    exit 1
    ;;
esac
