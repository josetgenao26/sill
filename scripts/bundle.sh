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

# Prefer a stable self-signed certificate over an ad-hoc signature.
#
# An ad-hoc signature makes the binary hash the identity, so every rebuild looks like a
# different app to macOS and the Accessibility grant is revoked. A certificate keeps the
# identity stable across rebuilds, so the permission is granted once.
#
# Create one in Keychain Access > Certificate Assistant > Create a Certificate:
#   Name: AltTabCloneDev / Identity Type: Self Signed Root / Type: Code Signing
SIGN_IDENTITY="${SIGN_IDENTITY:-AltTabCloneDev}"

if security find-identity -v -p codesigning | grep -q "$SIGN_IDENTITY"; then
    codesign --force --sign "$SIGN_IDENTITY" --identifier "$IDENTIFIER" "$APP"
    echo "Signed with '$SIGN_IDENTITY' — Accessibility permission survives rebuilds."
else
    codesign --force --sign - --identifier "$IDENTIFIER" "$APP"
    echo "WARNING: no '$SIGN_IDENTITY' certificate found; fell back to an ad-hoc signature."
    echo "         Accessibility permission will be revoked on every rebuild."
fi

echo "Built $APP"
