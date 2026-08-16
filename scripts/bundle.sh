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
APP="$ROOT/build/Sill.app"
IDENTIFIER="com.josetgenao.sill"

# Release builds are universal; debug builds are not.
#
# Nothing in this app is Apple Silicon specific — Accessibility, ScreenCaptureKit, event
# taps and AppKit all exist on Intel — but `swift build` targets only the host
# architecture, so a default build simply will not launch on an Intel Mac.
#
# Building both roughly doubles compile time, which is the wrong trade during development
# when the binary only ever runs on this machine. Release is where it matters.
#
# The ${ARCHS[@]+...} guard is not decoration: macOS ships bash 3.2, where expanding an
# empty array under `set -u` is an error rather than an empty list. Without it, every
# debug build fails while release builds keep working, since only debug leaves it empty.
ARCHS=()
if [ "$CONFIG" = "release" ]; then
    ARCHS=(--arch arm64 --arch x86_64)
fi

swift build --package-path "$ROOT" -c "$CONFIG" ${ARCHS[@]+"${ARCHS[@]}"}
BINARY="$(swift build --package-path "$ROOT" -c "$CONFIG" ${ARCHS[@]+"${ARCHS[@]}"} --show-bin-path)/Sill"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BINARY" "$APP/Contents/MacOS/Sill"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"

mkdir -p "$APP/Contents/Resources"
cp "$ROOT/Resources/Sill.icns" "$APP/Contents/Resources/"
# The menu bar mark ships as a PDF so macOS can rasterise it per display scale. Loaded as
# a template image, which is what lets the system invert it in dark mode.
cp "$ROOT/Resources/menubar-template.pdf" "$APP/Contents/Resources/"

# Prefer a stable self-signed certificate over an ad-hoc signature.
#
# An ad-hoc signature makes the binary hash the identity, so every rebuild looks like a
# different app to macOS and the Accessibility grant is revoked. A certificate keeps the
# identity stable across rebuilds, so the permission is granted once.
#
# Create one in Keychain Access > Certificate Assistant > Create a Certificate:
#   Name: SillDev / Identity Type: Self Signed Root / Type: Code Signing
#
# AltTabCloneDev is accepted as well: it is the certificate created under the project's
# former name, and it signs just as well as a renamed one would. Which certificate signs a
# local development build carries no meaning — forcing a new one would only mean granting
# the Accessibility permission again for nothing.
SIGN_IDENTITY=""
for candidate in "${SIGN_IDENTITY_OVERRIDE:-}" SillDev AltTabCloneDev; do
    [ -n "$candidate" ] || continue
    if security find-identity -v -p codesigning | grep -q "$candidate"; then
        SIGN_IDENTITY="$candidate"
        break
    fi
done

if [ -n "$SIGN_IDENTITY" ]; then
    codesign --force --sign "$SIGN_IDENTITY" --identifier "$IDENTIFIER" "$APP"
    echo "Signed with '$SIGN_IDENTITY' — Accessibility permission survives rebuilds."
else
    codesign --force --sign - --identifier "$IDENTIFIER" "$APP"
    echo "WARNING: no signing certificate found; fell back to an ad-hoc signature."
    echo "         Accessibility permission will be revoked on every rebuild."
fi

echo "Built $APP"
