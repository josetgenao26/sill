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
    private enum Key {
        static let tab: Int64 = 48
        static let escape: Int64 = 53
    }

    private let report: Report
    private var tap: CFMachPort?

    /// Windows are snapshotted when cycling starts, not re-read on every Tab. Re-reading
    /// mid-gesture would let the list reorder underneath the user as raising changes
    /// window order, so Tab would stop meaning "the next one".
    private var snapshot: [WindowInfo] = []
    private var selection = 0
    private var isCycling = false

    init(report: Report) {
        self.report = report
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

        let optionHeld = event.flags.contains(.maskAlternate)

        switch type {
        case .keyDown:
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

            if keyCode == Key.tab, optionHeld {
                advance(reverse: event.flags.contains(.maskShift))
                return nil  // consumed: the focused app must not also receive this Tab
            }
            if keyCode == Key.escape, isCycling {
                cancel()
                return nil
            }

        case .flagsChanged:
            // Releasing Option is the commit signal. flagsChanged is the only event that
            // reports a modifier going up, which a plain hotkey registration never sees.
            if isCycling, !optionHeld {
                commit()
            }

        default:
            break
        }

        return Unmanaged.passUnretained(event)
    }

    // MARK: - State machine

    private func advance(reverse: Bool) {
        if !isCycling {
            snapshot = WindowEnumerator.allWindows()
            guard !snapshot.isEmpty else { return }
            isCycling = true
            // Start on the second window: the first Tab should land on the previously
            // used window, which is what makes a switcher useful for toggling.
            selection = snapshot.count > 1 ? 1 : 0
            report.add("cycle start — \(snapshot.count) windows")
        } else {
            let step = reverse ? -1 : 1
            selection = (selection + step + snapshot.count) % snapshot.count
        }

        let window = snapshot[selection]
        let title = window.title.isEmpty ? "(untitled)" : window.title
        report.add("  [\(selection)] \(window.appName) — \(title)")
    }

    private func commit() {
        defer { isCycling = false }
        guard let target = snapshot[safe: selection] else { return }

        report.add("commit → \(target.appName) — \(target.title)")
        let outcome = WindowRaiser.raise(target)
        report.add("  raised: \(outcome.raised), activated: \(outcome.activated)")
    }

    private func cancel() {
        isCycling = false
        report.add("cancelled")
    }
}
