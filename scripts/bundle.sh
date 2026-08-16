#!/usr/bin/env bash
#
# Builds the executable and wraps it in a .app bundle with a stable code signature.
#
# The bundle is not cosmetic. macOS grants Accessibility permission to a code identity,
# not to a path, so a bare executable loses its permission on every rebuild. Signing the
# bundle with a fixed --identifier keeps that grant across rebuilds.

set -euo pipefail

CONFIG="${1:-debug}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/build/AltTabClone.app"
IDENTIFIER="com.josetgenao.alttabclone"

swift build --package-path "$ROOT" -c "$CONFIG"
BINARY="$(swift build --package-path "$ROOT" -c "$CONFIG" --show-bin-path)/AltTabClone"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BINARY" "$APP/Contents/MacOS/AltTabClone"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"

# Ad-hoc signature ("-") with an explicit identifier. Ad-hoc is enough for local
# development; a self-signed certificate becomes worthwhile only if macOS starts
# re-prompting for permission on every rebuild.
codesign --force --sign - --identifier "$IDENTIFIER" "$APP"

echo "Built $APP"
