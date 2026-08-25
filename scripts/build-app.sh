#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
SCRATCH="${RATAMER_SCRATCH:-$TMPDIR/ratamer-build}"
ICON_SRC="${ICON_SRC:-$ROOT/screenshots/icone.png}"

# ======================================================================
# KEYCHAIN: try to unlock the default keychain without a password first
# (works while you are logged in). Export BUILD_KEYCHAIN_PASSWORD to have
# it unlocked and configured for non-interactive codesigning.
# ======================================================================
if command -v security >/dev/null 2>&1; then
    DEFAULT_KEYCHAIN="$(security default-keychain 2>/dev/null | tr -d '"' | xargs)"
    if [ -n "${DEFAULT_KEYCHAIN}" ] && [ -f "${DEFAULT_KEYCHAIN}" ]; then
        if [ -n "${BUILD_KEYCHAIN_PASSWORD:-}" ]; then
            security unlock-keychain -p "${BUILD_KEYCHAIN_PASSWORD}" "${DEFAULT_KEYCHAIN}" 2>/dev/null || true
            security set-keychain-settings -t 3600 -l "${DEFAULT_KEYCHAIN}" 2>/dev/null || true
            security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "${BUILD_KEYCHAIN_PASSWORD}" "${DEFAULT_KEYCHAIN}" 2>/dev/null || {
                echo "Warning: could not configure keychain partitions; codesign may prompt for permission."
            }
        else
            security unlock-keychain "${DEFAULT_KEYCHAIN}" 2>/dev/null || \
                echo "Note: keychain is locked; codesign may prompt. Export BUILD_KEYCHAIN_PASSWORD to avoid prompts."
        fi
    else
        echo "Warning: default keychain not found; signing may fail."
    fi
fi

# ======================================================================
# UNIVERSAL BUILD: Apple Silicon + Intel (arm64 + x86_64) in one binary.
# ======================================================================
ARCHS=(--arch arm64 --arch x86_64)

echo "==> Building universal binary (arm64 + x86_64)..."
swift build -c release --product RaTamer --scratch-path "$SCRATCH" "${ARCHS[@]}"
BIN_DIR="$(swift build -c release --product RaTamer --scratch-path "$SCRATCH" "${ARCHS[@]}" --show-bin-path)"
BIN="$BIN_DIR/RaTamer"

echo "==> Generating icon..."
swift run IconGen "$ROOT/build/icon" "$ICON_SRC"

APP="$ROOT/build/RaTamer.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/RaTamer"
cp "$ROOT/build/icon/RaTamer.icns" "$APP/Contents/Resources/RaTamer.icns"
cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>RaTamer</string>
    <key>CFBundleIdentifier</key><string>com.rattamer</string>
    <key>CFBundleExecutable</key><string>RaTamer</string>
    <key>CFBundleIconFile</key><string>RaTamer</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0.2</string>
    <key>CFBundleVersion</key><string>5</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
</dict>
</plist>
EOF
chmod +x "$APP/Contents/MacOS/RaTamer"

# ======================================================================
# SIGNING: use the stable local identity when available so the cdhash
# (and the Accessibility approval tied to it) survives rebuilds. Fresh
# clones fall back to ad-hoc signing — those builds change identity every
# time, so macOS will ask to re-grant Accessibility after each rebuild.
# ======================================================================
if [ -z "${CODESIGN_IDENTITY:-}" ]; then
    CODESIGN_IDENTITY="$(security find-identity 2>/dev/null | awk '/RatTamer Local Signing/ {print $2; exit}')"
fi
if [ -z "${CODESIGN_IDENTITY}" ]; then
    echo "Note: \"RatTamer Local Signing\" certificate not found — using an ad-hoc signature."
    echo "      Ad-hoc builds get a new identity every build, so macOS re-asks for Accessibility."
    echo "      To create a stable certificate: open Keychain Access → Certificate Assistant →"
    echo "      Create a Certificate… (self-signed, Code Signing type, name: RatTamer Local Signing)."
    CODESIGN_IDENTITY="-"
fi
codesign --force --sign "$CODESIGN_IDENTITY" "$APP"

echo "==> Architectures:"
lipo -info "$APP/Contents/MacOS/RaTamer"
echo "Built and signed $APP (identity: $CODESIGN_IDENTITY)"
