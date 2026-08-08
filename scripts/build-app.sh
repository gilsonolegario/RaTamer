#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
SCRATCH="${RATTAMER_SCRATCH:-$TMPDIR/rattamer-build}"
swift build -c release --scratch-path "$SCRATCH"
swift run IconGen
BIN="$SCRATCH/arm64-apple-macosx/release/RatTamer"
APP="$ROOT/build/RatTamer.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/RatTamer"
cp "$ROOT/build/icon/RatTamer.icns" "$APP/Contents/Resources/RatTamer.icns"
cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>RatTamer</string>
    <key>CFBundleIdentifier</key><string>com.rattamer</string>
    <key>CFBundleExecutable</key><string>RatTamer</string>
    <key>CFBundleIconFile</key><string>RatTamer</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.9.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
</dict>
</plist>
EOF
chmod +x "$APP/Contents/MacOS/RatTamer"
if [ -z "${CODESIGN_IDENTITY:-}" ]; then
    CODESIGN_IDENTITY="$(security find-identity 2>/dev/null | awk '/RatTamer Local Signing/ {print $2; exit}')"
fi
CODESIGN_IDENTITY="${CODESIGN_IDENTITY:--}"
codesign --force --sign "$CODESIGN_IDENTITY" "$APP"
echo "Built and signed $APP"
