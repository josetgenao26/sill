import AppKit
import CoreGraphics

/// Intercepts Option+Tab and drives the switcher's selection state.
///
/// The gesture is a held interaction, not a single shortcut: holding Option keeps the
/// switcher open, Tab advances the selection, and releasing Option commits it. That shape
/// is why this needs an event tap rather than a registered hotkey — a hotkey API reports
/// the keypress but not the modifier being held or released afterwards.
///
/// Safety: this tap consumes keystrokes before they reach any app. It only ever consumes
/// Tab while Option is held, so a bug here cannot swallow ordinary typing. The caller is
/// still expected to bound the process lifetime while this is under development.
final class HotkeyMonitor {
    /// Escape stays fixed. It cancels the switcher, and letting it be rebound would let a
    /// user configure away the only way out of a gesture.
    private static let escapeKey: Int64 = 53

    /// Which windows a gesture cycles through.
    ///
    /// Both scopes share one state machine — only the snapshot taken at the start of a
    /// cycle differs — because the gesture, the reverse direction, the commit on release
    /// and the cancel are all identical.
    private enum Scope {
        case allWindows
        case currentApp
    }

    private let report: Report
    private let history: WindowHistory
    private let panel = SwitcherPanel()
    private let thumbnails: ThumbnailProvider
    private var tap: CFMachPort?

    /// Windows are snapshotted when cycling starts, not re-read on every Tab. Re-reading
    /// mid-gesture would let the list reorder underneath the user as raising changes
    /// window order, so Tab would stop meaning "the next one".
    private var snapshot: [WindowInfo] = []
    private var selection = 0
    private var isCycling = false

    /// The modifiers whose release ends the current gesture. Captured when a cycle begins
    /// rather than read back from preferences, so rebinding the shortcut mid-gesture
    /// cannot strand the switcher waiting for a key that is no longer part of it.
    private var holdModifiers: CGEventFlags = []

    init(report: Report, history: WindowHistory, thumbnails: ThumbnailProvider) {
        self.report = report
        self.history = history
        self.thumbnails = thumbnails

        // Pointing at an entry selects it, so releasing Option commits whatever is under
        // the cursor. Clicking commits straight away, without waiting for the release.
        panel.onHover = { [weak self] index in
            guard let self, isCycling else { return }
            selection = index
            panel.highlight(index)
        }
        panel.onClick = { [weak self] index in
            guard let self, isCycling else { return }
            selection = index
            commit()
        }
    }

    // MARK: - Lifecycle

    /// Installs the tap. Returns false if the system refuses, which in practice means the
    /// Accessibility permission is missing.
    func start() -> Bool {
        let mask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            // .defaultTap (rather than .listenOnly) is what allows returning nil to
            // swallow an event, which is required so Tab does not also reach the app.
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                // The callback is a C function pointer and cannot capture context, so the
                // instance is passed through refcon and recovered here.
                let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(refcon).takeUnretainedValue()
                return monitor.handle(type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }

        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    // MARK: - Event handling

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // The system disables a tap that responds too slowly, and does so silently.
        // Without re-enabling here the switcher would simply stop working after a while.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            report.add("tap disabled by system (\(type.rawValue)) — re-enabling")
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return nil
        }

        // Events this app synthesised come back through its own tap. Without skipping
        // them, the Control+Arrow posted to change Space could be read as user input.
        if event.getIntegerValueField(.eventSourceUserData) == SpaceSwitcher.syntheticMarker {
            return Unmanaged.passUnretained(event)
        }

        switch type {
        case .keyDown:
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            let reverse = event.flags.contains(.maskShift)

            // Space switching is discrete, not a held cycle: there is no public way to
            // enumerate Spaces, so there is nothing to show a list of and nothing to
            // commit on release. One press, one step.
            let space = Preferences.spaceShortcut
            if keyCode == space.keyCode, space.matches(flags: event.flags) {
                report.add("space: \(reverse ? "previous" : "next")")
                SpaceSwitcher.move(next: !reverse)
                return nil
            }

            for (shortcut, scope) in [
                (Preferences.allWindowsShortcut, Scope.allWindows),
                (Preferences.sameAppShortcut, Scope.currentApp),
            ] where keyCode == shortcut.keyCode && shortcut.matches(flags: event.flags) {
                if !isCycling {
                    holdModifiers = shortcut.holdModifiers
                }
                advance(reverse: reverse, scope: scope)
                // Consumed: the focused app must not also receive this keystroke.
                return nil
            }

            if keyCode == Self.escapeKey, isCycling {
                cancel()
                return nil
            }

        case .flagsChanged:
            // Releasing the held modifiers is the commit signal. flagsChanged is the only
            // event reporting a modifier going up, which a hotkey registration never sees.
            if isCycling, event.flags.intersection(holdModifiers).isEmpty {
                commit()
            }

        default:
            break
        }

        return Unmanaged.passUnretained(event)
    }

    // MARK: - State machine

    private func advance(reverse: Bool, scope: Scope) {
        if !isCycling {
            let live = WindowEnumerator.allWindows()
            history.prune(keeping: live)

            // The scope is fixed when the cycle begins. Reading it per keystroke would let
            // the set change underneath the user as raising moves focus to another app.
            switch scope {
            case .allWindows:
                snapshot = history.sorted(live)
            case .currentApp:
                let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier
                snapshot = history.sorted(live.filter { $0.pid == pid })
            }

            guard !snapshot.isEmpty else { return }
            isCycling = true
            // Start on the second window. With MRU ordering the first entry is the window
            // already in use, so the second is the one the user was in before it — which
            // is what makes a single Option+Tab toggle back and forth.
            selection = snapshot.count > 1 ? 1 : 0
            let layout = Preferences.layout
            report.add("cycle start — \(snapshot.count) windows (\(scope), \(layout.rawValue))")

            // Shown immediately with whatever is already cached. Captures are fetched
            // afterwards and dropped in as they arrive, so the panel never waits on
            // ScreenCaptureKit before appearing.
            panel.show(
                snapshot,
                selection: selection,
                layout: layout,
                thumbnails: layout.needsCapture ? thumbnails : nil
            )

            if layout.needsCapture {
                thumbnails.fetch(for: snapshot) { [weak self] key, image in
                    self?.panel.setThumbnail(image, for: key)
                }
            }
        } else {
            let step = reverse ? -1 : 1
            selection = (selection + step + snapshot.count) % snapshot.count
            panel.highlight(selection)
        }

        let window = snapshot[selection]
        let title = window.title.isEmpty ? "(untitled)" : window.title
        report.add("  [\(selection)] \(window.appName) — \(title)")
    }

    private func commit() {
        defer { isCycling = false }
        panel.hide()
        guard let target = snapshot[safe: selection] else { return }

        report.add("commit → \(target.appName) — \(target.title)")
        let outcome = WindowRaiser.raise(target)
        report.add("  raised: \(outcome.raised), activated: \(outcome.activated)")

        // Record directly rather than waiting for the observer to report our own switch.
        // The notification may arrive after the next gesture starts, which would leave
        // the ordering one step behind the user.
        history.recordFocus(target.element)
    }

    private func cancel() {
        isCycling = false
        panel.hide()
        report.add("cancelled")
    }
}
