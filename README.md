# Sill

A window switcher for macOS. Hold Option, press Tab, pick a window — including windows of
the same app, which the built-in Command+Tab collapses into a single icon.

Built from scratch to learn how macOS window management actually works underneath: the
Accessibility API, ScreenCaptureKit, event taps, and the permission system around them.

**[Website](https://josetgenao26.github.io/sill/)** · **[Download](https://github.com/josetgenao26/sill/releases/latest)**

## Why

`Command+Tab` switches between **applications**. If you have three editor windows open on
three different projects, macOS treats them as one destination and drops you in whichever
one it last considered main.

Sill switches between **windows**. Every window is its own entry, ordered by how recently
you used it, so a single Option+Tab returns you to where you just were.

## Install

Download `Sill.app` from [Releases](../../releases), move it to `/Applications`, and open
it.

macOS will refuse the first launch, because the app is signed with a self-signed
certificate rather than a paid Apple Developer ID. To open it anyway: **right-click the
app → Open**, then confirm. This is required once.

Then grant **Accessibility** in System Settings → Privacy & Security. Sill waits for it
and continues on its own once granted. The Thumbnails layout also asks for **Screen
Recording**; the other two layouts never need it.

Start Sill before you need it. Ordering is built by watching focus over time, so a
switcher that just launched has no history to answer "the window I was in before" with.
Turn on **Start at Login** from the menu bar to avoid thinking about it.

## Using it

| | |
| --- | --- |
| **⌥ + Tab** | Cycle every window |
| **⌥ + `** | Cycle windows of the current app only |
| **+ Shift** | Cycle backwards |
| **Release ⌥** | Switch to the highlighted window |
| **Point / click** | Select with the mouse; a click switches immediately |
| **Escape** | Cancel |

Both shortcuts are rebindable in Settings. A trigger must include Command, Option or
Control: the gesture commits when you release the modifier, so a trigger without one would
record cleanly and then never fire.

### Layouts

| Layout | Best at | Weak at |
| --- | --- | --- |
| **List** | Long titles; telling apart windows of one app | Scanning many windows at a glance |
| **Thumbnails** | Recognising a window by its content | Needs Screen Recording; titles truncate |
| **App Icons** | Fastest scan across different apps | Windows of one app look identical |

Also configurable: panel size, which display it opens on, and how many windows it lists.

## Requirements

macOS 14 or later. Universal — Apple Silicon and Intel.

## Building

```bash
git clone <this repo>
cd sill
./scripts/bundle.sh          # debug, current architecture
./scripts/bundle.sh release  # universal
open build/Sill.app --args --hotkey
```

Activity is logged to `~/Library/Logs/Sill.log`, which is the fastest way to see what the
switcher thinks is happening.

### Capturing the panel

The panel only exists while the modifier is held, and every screenshot shortcut needs
modifiers of its own — so it cannot be photographed the normal way. `--demo` holds it open
for a set number of seconds, then hides it and carries on as the switcher:

```bash
open build/Sill.app --args --demo 20
```

Then `Cmd+Shift+4`, `Space`, and click the panel.

### A signing certificate, before your first build

Without one, macOS revokes the Accessibility permission on **every rebuild**, and you will
re-grant it by hand every time you change a line.

macOS grants Accessibility to a *code identity*, not to a file path. An ad-hoc signature
makes the binary hash the identity, so each rebuild reads as a different app. A
certificate keeps that identity stable.

In **Keychain Access → Certificate Assistant → Create a Certificate**, create `SillDev`
as a **Self Signed Root** of type **Code Signing**. Verify with:

```bash
security find-identity -v -p codesigning
```

If Certificate Assistant fails with "The specified item could not be found in the
keychain" — a long-standing bug, not your mistake — create it from the terminal instead:

```bash
openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
  -keyout /tmp/sill.key -out /tmp/sill.crt -subj "/CN=SillDev" \
  -addext "basicConstraints=critical,CA:false" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=critical,codeSigning" \
&& openssl pkcs12 -export -legacy -out /tmp/sill.p12 \
  -inkey /tmp/sill.key -in /tmp/sill.crt -passout pass:silldev \
&& security import /tmp/sill.p12 -k ~/Library/Keychains/login.keychain-db \
  -P silldev -T /usr/bin/codesign -A \
&& security add-trusted-cert -r trustRoot \
  -k ~/Library/Keychains/login.keychain-db /tmp/sill.crt \
&& rm -f /tmp/sill.key /tmp/sill.crt /tmp/sill.p12 \
&& security find-identity -v -p codesigning
```

`-legacy` is required: OpenSSL 3 writes PKCS12 with ciphers Apple's `security` cannot
read, and reports the failure as a wrong password.

`scripts/bundle.sh` picks the certificate up automatically and warns loudly if it is
missing.

## How it works

- **Enumeration** uses the Accessibility API rather than `CGWindowListCopyWindowInfo`.
  CGWindowList can list windows, but returns inert metadata with no way to raise one.
  Accessibility returns live `AXUIElement` handles that support `kAXRaiseAction`.
- **Focus** takes three steps that each cover a different gap: mark the window main, raise
  it within its app, and activate the app. Any one alone leaves the window visible but
  unfocused, or focuses the wrong window of the right app.
- **Ordering** is accumulated by watching focus changes, because macOS publishes no
  most-recently-used window list. That is why Sill has to keep running to be useful.
- **The gesture** needs a `CGEvent` tap, not a registered hotkey: the commit signal is the
  modifier being *released*, and only `flagsChanged` reports that.
- **The panel** never takes focus. If it did, Sill would become the most recently used
  window and corrupt its own ordering with its own UI.

## Known limitations

**Windows on other Spaces are not listed.** In a full-screen Space, Sill sees two windows
instead of twelve. The Accessibility API only reports windows on the current Space.
`CGWindowListCopyWindowInfo(.optionAll)` does see across Spaces, but raising a window
needs an `AXUIElement`, which off-Space windows do not appear to have.

**Switching Spaces is not possible without private APIs.** Worth recording so nobody
repeats the attempt. macOS has no public API for changing Space, so the obvious workaround
is synthesising its own Control+Arrow shortcut. It does not work, and not because the
attempt was wrong:

- The trigger fires and the code runs.
- Posting works — the same code posting a plain `x` types an `x`.
- Posting Control+Arrow changes nothing: inside the event tap or from a menu action, at
  the session tap or the HID tap, with Mission Control's shortcuts verified enabled.

macOS accepts synthesised keystrokes but refuses to let them fire its own symbolic
hotkeys, deliberately — otherwise any app could drive Mission Control and the Dock. The
only remaining route is private CoreGraphics calls.

**Apps that expose no Accessibility tree** — some Electron, Java and X11 hosts — are
skipped.

## Prior art

[AltTab](https://github.com/lwouis/alt-tab-macos) is the mature, full-featured window
switcher for macOS, and worth your money if you want one that is finished. Sill is a
from-scratch implementation written to understand the problem, not a fork of it.

One difference worth noting: AltTab reaches for private CoreGraphics APIs in places. Sill
does not, which is why cross-Space support is absent here rather than merely unfinished.

## License

MIT — see [LICENSE](LICENSE).
