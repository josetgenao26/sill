# AltTabClone

A window switcher for macOS, built from scratch to learn how window management works
underneath: the Accessibility API, ScreenCaptureKit, and event taps.

## Status

Step 1 — enumerate windows through the Accessibility API and print them.
No UI, no hotkey, no thumbnails yet.

## One-time setup: a signing certificate

Do this before the first build, or the Accessibility permission has to be granted again
after every single rebuild.

In **Keychain Access > Certificate Assistant > Create a Certificate...**:

- **Name**: `AltTabCloneDev`
- **Identity Type**: `Self Signed Root`
- **Certificate Type**: `Code Signing`

Verify it exists:

```bash
security find-identity -v -p codesigning
```

## Build and run

```bash
./scripts/bundle.sh
open build/AltTabClone.app
tail -f ~/Library/Logs/AltTabClone.log
```

The first run waits up to 90 seconds for permission. Enable **AltTabClone** in
**System Settings > Privacy & Security > Accessibility** and the run continues on its own.

Launch with `open`, not by executable path: running it from a shell makes macOS attribute
the Accessibility request to the parent terminal instead of to this app. Because `open`
detaches stdout, results go to `~/Library/Logs/AltTabClone.log`.

## Why a .app bundle instead of a bare executable

macOS grants Accessibility permission to a *code identity*, not to a file path.

An ad-hoc signature makes the binary hash the identity, so every rebuild reads as a
different app and the grant is revoked. A self-signed certificate keeps the identity
stable, so permission is granted once and survives rebuilds.

`scripts/bundle.sh` uses the certificate when present and warns loudly when it is not.

If a rebuild ever does invalidate the entry, remove **AltTabClone** from the Accessibility
list with the minus button and add it back — toggling it off and on is not always enough.

## Why the Accessibility API and not CGWindowList

`CGWindowListCopyWindowInfo` can enumerate windows, but it returns inert metadata —
there is no way to raise a window from it. Accessibility returns live `AXUIElement`
handles that support `kAXRaiseAction`, which the switcher needs to actually change focus.

## Known gaps

These are deliberate omissions at this stage, not bugs:

- Windows on other Spaces are not visible (requires private CoreGraphics APIs).
- Fullscreen windows are not handled.
- Apps that expose no Accessibility tree (some Electron, Java, and X11 hosts) are skipped.
