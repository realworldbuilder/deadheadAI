#!/bin/zsh
# Build Deadheads.AI and install it on a connected iPhone.
# Usage: ./run-on-phone.sh
# Requires: iPhone plugged in (or on same network with wireless debugging),
# unlocked, and trusted with this Mac. Developer Mode must be enabled on the
# phone (Settings > Privacy & Security > Developer Mode).
set -e
cd "$(dirname "$0")"

echo "→ Looking for a connected iPhone…"
DEVICE_LINE=$(xcrun devicectl list devices 2>/dev/null | grep -E 'available.*iPhone|connected.*iPhone|iPhone.*(available|connected)' | head -1 || true)
if [[ -z "$DEVICE_LINE" ]]; then
  echo "✗ No available iPhone found."
  echo "  Plug your iPhone in with a cable, unlock it, tap 'Trust', then rerun."
  echo "  (Check with: xcrun devicectl list devices)"
  exit 1
fi
DEVICE_ID=$(echo "$DEVICE_LINE" | grep -oE '[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}' | head -1)
echo "→ Found device: $DEVICE_ID"

echo "→ Regenerating project…"
xcodegen generate > /dev/null

echo "→ Building for device (signing with your Apple Development certificate)…"
xcodebuild -project ShakedownAI.xcodeproj -scheme ShakedownAI \
  -destination "generic/platform=iOS" \
  -derivedDataPath build-device \
  -allowProvisioningUpdates \
  -allowProvisioningDeviceRegistration \
  build | grep -E 'error:|warning: .*[Ss]ign|BUILD' | tail -5

APP=build-device/Build/Products/Debug-iphoneos/ShakedownAI.app
if [[ ! -d "$APP" ]]; then
  echo "✗ Build product not found. Open ShakedownAI.xcodeproj in Xcode,"
  echo "  check Signing & Capabilities, plug in the phone, and press Run once."
  exit 1
fi

echo "→ Installing on iPhone…"
xcrun devicectl device install app --device "$DEVICE_ID" "$APP"

echo "→ Launching…"
xcrun devicectl device process launch --device "$DEVICE_ID" com.deadhead.ai || true

echo "✓ Deadheads.AI is on your phone."
echo "  Free Apple ID note: the install expires after 7 days — rerun this script to refresh."
