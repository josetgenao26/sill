# AltTabClone

A window switcher for macOS, built from scratch to learn how window management works
underneath: the Accessibility API, ScreenCaptureKit, and event taps.

## Status

Working switcher: window enumeration, most-recently-used ordering, an Option+Tab held
gesture with forward and reverse cycling, a floating panel, and focus switching.

No thumbnails yet, and it is not yet installed to launch at login.

## Using it

```bash
./scripts/bundle.sh
open build/AltTabClone.app --args --hotkey
```

- **Hold Option, press Tab** — cycle forward
- **Shift+Tab** while holding Option — cycle backward
- **Release Option** — switch to the highlighted window
- **Escape** — cancel

It runs until killed:

```bash
pkill -f AltTabClone
```

Start it before you need it. Ordering is built by watching focus over time, so a switcher
that just launched has no history and cannot know which window you were in before.

Activity is logged to `~/Library/Logs/AltTabClone.log`.

### Other modes

```bash
open build/AltTabClone.app                     # list windows, then exit
open build/AltTabClone.app --args --raise 3    # raise one window by index
```

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

- **Windows on other Spaces are not listed.** In a full-screen Space the switcher sees two
  windows instead of twelve. The Accessibility API only reports windows on the current
  Space. `CGWindowListCopyWindowInfo(.optionAll)` does see across Spaces, but raising a
  window needs an `AXUIElement`, which off-Space windows do not appear to have.
- Apps that expose no Accessibility tree (some Electron, Java, and X11 hosts) are skipped.

### Switching Spaces is not possible from a sandboxed public API

Worth recording so it is not attempted again. macOS has no public API for changing Space,
so the obvious workaround is to synthesise its own Control+Arrow shortcut. That does not
work, and the reason is not a bug in the attempt:

- The trigger fires and the code runs — it logs every time.
- Posting works: the same code posting a plain `x` types an `x`.
- Posting Control+Arrow changes nothing, from inside the event tap or from a menu action,
  at the session tap or the HID tap.

macOS accepts synthesised keystrokes but refuses to let them fire its own symbolic
hotkeys. That is deliberate: otherwise any app could drive Mission Control and the Dock.
The only remaining route is private CoreGraphics calls (`CGSSetWorkspace` and relatives),
which is what AltTab uses.
