#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
SCRATCH="${RATTAMER_SCRATCH:-$TMPDIR/rattamer-build}"
ICON_SRC="${ICON_SRC:-$ROOT/screenshots/icone.png}"
KEYCHAIN_PASSWORD="${BUILD_KEYCHAIN_PASSWORD:-REDACTED}"

# ======================================================================
# KEYCHAIN: desbloqueia o keychain padrão e configura partições para
# evitar prompts durante a assinatura (padrão validado no AppArquipelago).
# ======================================================================
if command -v security >/dev/null 2>&1; then
    DEFAULT_KEYCHAIN="$(security default-keychain 2>/dev/null | tr -d '"' | xargs)"
    if [ -n "${DEFAULT_KEYCHAIN}" ] && [ -f "${DEFAULT_KEYCHAIN}" ]; then
        security unlock-keychain -p "${KEYCHAIN_PASSWORD}" "${DEFAULT_KEYCHAIN}" 2>/dev/null || {
            echo "Aviso: falha ao desbloquear com a senha fornecida. Tentando sem senha..."
            security unlock-keychain "${DEFAULT_KEYCHAIN}" 2>/dev/null || true
        }
        security set-keychain-settings -t 3600 -l "${DEFAULT_KEYCHAIN}" 2>/dev/null || true
        security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "${KEYCHAIN_PASSWORD}" "${DEFAULT_KEYCHAIN}" 2>/dev/null || {
            echo "Aviso: falha ao configurar partições do keychain. Pode pedir senha durante a assinatura."
        }
    else
        echo "Aviso: keychain padrão não encontrado. Pode haver problemas de assinatura."
    fi
fi

swift build -c release --scratch-path "$SCRATCH"
swift run IconGen "$ROOT/build/icon" "$ICON_SRC"
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
    <key>CFBundleShortVersionString</key><string>1.0.2</string>
    <key>CFBundleVersion</key><string>4</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
</dict>
</plist>
EOF
chmod +x "$APP/Contents/MacOS/RatTamer"
# Assine SEMPRE com a identidade local estável "RatTamer Local Signing".
# Nunca caia em ad-hoc: o DR muda a cada build e o macOS revoga a permissão
# de Accessibility toda vez, forçando o usuário a re-adicionar o app.
if [ -z "${CODESIGN_IDENTITY:-}" ]; then
    CODESIGN_IDENTITY="$(security find-identity 2>/dev/null | awk '/RatTamer Local Signing/ {print $2; exit}')"
fi
if [ -z "${CODESIGN_IDENTITY}" ]; then
    echo "ERRO: identidade 'RatTamer Local Signing' não encontrada no keychain." >&2
    echo "Crie com: security create-keypair && ... ou adicione o cert local." >&2
    exit 1
fi
codesign --force --sign "$CODESIGN_IDENTITY" "$APP"
echo "Built and signed $APP (identity: $CODESIGN_IDENTITY)"
