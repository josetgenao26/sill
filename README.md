# AltTabClone

A window switcher for macOS, built from scratch to learn how window management works
underneath: the Accessibility API, ScreenCaptureKit, and event taps.

## Status

Step 1 — enumerate windows through the Accessibility API and print them.
No UI, no hotkey, no thumbnails yet.

## Build and run

```bash
./scripts/bundle.sh
./build/AltTabClone.app/Contents/MacOS/AltTabClone
```

The first run exits asking for permission. Grant it in
**System Settings > Privacy & Security > Accessibility**, then run it again.

## Why a .app bundle instead of a bare executable

macOS grants Accessibility permission to a *code identity*, not to a file path. A bare
executable gets a new identity on every rebuild, so the permission is revoked each time
and has to be granted again.

`scripts/bundle.sh` wraps the binary in a .app and signs it with a fixed
`--identifier`, which keeps the grant stable across rebuilds.

If macOS ever starts re-prompting anyway, replace the ad-hoc signature (`--sign -`) with
a self-signed certificate from Keychain Access.

## Why the Accessibility API and not CGWindowList

`CGWindowListCopyWindowInfo` can enumerate windows, but it returns inert metadata —
there is no way to raise a window from it. Accessibility returns live `AXUIElement`
handles that support `kAXRaiseAction`, which the switcher needs to actually change focus.

## Known gaps

These are deliberate omissions at this stage, not bugs:

- Windows on other Spaces are not visible (requires private CoreGraphics APIs).
- Fullscreen windows are not handled.
- Apps that expose no Accessibility tree (some Electron, Java, and X11 hosts) are skipped.
