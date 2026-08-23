#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION="${1:-}"
if [ -z "$VERSION" ]; then
    VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' build/RatTamer.app/Contents/Info.plist 2>/dev/null || echo "")"
fi
if [ -z "$VERSION" ]; then
    echo "No version given and no previous build found. Run ./scripts/build-app.sh first or pass a version:"
    echo "  $0 0.9.0"
    exit 1
fi

DRAFT=""
if [ "${2:-}" = "draft" ]; then
    DRAFT="--draft"
fi

echo "==> Building app (assinado com identidade local estável)..."
./scripts/build-app.sh

echo "==> Creating zip..."
ZIP="$ROOT/build/RatTamer-$VERSION.zip"
rm -f "$ZIP"
ditto -c -k --keepParent build/RatTamer.app "$ZIP"
echo "    $ZIP"

if ! gh auth status &>/dev/null; then
    echo "gh is not authenticated. Skipping release upload. Zip is ready:"
    echo "  $ZIP"
    exit 0
fi

TAG="v$VERSION"
echo "==> Creating GitHub release $TAG..."
if gh release view "$TAG" --repo gilsonolegario/RaTamer &>/dev/null; then
    echo "    Release $TAG already exists - uploading asset."
    gh release upload "$TAG" "$ZIP" --repo gilsonolegario/RaTamer --clobber
else
    gh release create "$TAG" "$ZIP" \
        --repo gilsonolegario/RaTamer \
        --title "RatTamer $VERSION" \
        --notes "Pre-built app bundle (ad-hoc signed, **not notarized**). See the README 'First launch (macOS 15+)' section for how to open it on macOS 15+." \
        $DRAFT
fi
echo "==> Done."
