import AppKit
import Foundation

// Probe driver. Three modes, each verifying one layer before the next is built on it:
//
//   open build/AltTabClone.app                     list windows
//   open build/AltTabClone.app --args --raise 3    raise and focus one window
//   open build/AltTabClone.app --args --hotkey     Option+Tab switching, no UI yet
//
// The hotkey mode logs its selection instead of drawing it. Whether the state machine
// tracks the gesture correctly is a separate question from how it looks, and mixing the
// two would make a failure in either one hard to attribute.

let arguments = CommandLine.arguments

// An accessory app has no Dock icon or menu bar but can still own windows and taps,
// which is what a switcher needs. NSApplication must exist before any of that.
let application = NSApplication.shared
application.setActivationPolicy(.accessory)

/// Lets AppKit process pending events.
///
/// Activation is an asynchronous request to the window server, not a synchronous state
/// change. A process that exits without pumping its run loop never delivers the request —
/// and `activate()` still returns true, so nothing reports the failure.
func pump(_ seconds: TimeInterval) {
    RunLoop.current.run(until: Date().addingTimeInterval(seconds))
}

let report = Report()

func describe(_ window: WindowInfo, index: Int? = nil) -> String {
    let label = index.map { "[\($0)] " } ?? ""
    let title = window.title.isEmpty ? "(untitled)" : window.title
    let flags = [window.isMinimized ? "minimized" : nil, window.isMain ? "MAIN" : nil]
        .compactMap { $0 }
        .joined(separator: ",")
    let suffix = flags.isEmpty ? "" : " [\(flags)]"
    return "  \(label)\(window.appName) — \(title)\(suffix)  pid:\(window.pid)"
}

guard AX.waitForTrust(timeout: 300) else {
    report.add("Accessibility: DENIED (timed out)")
    report.add("Enable AltTabClone in System Settings > Privacy & Security > Accessibility.")
    report.close()
    exit(1)
}

// MARK: - Hotkey mode

if arguments.contains("--hotkey") {
    // Runs until killed. The bounded lifetime this had was a safety net while the event tap
    // was unproven, since a tap swallowing the wrong keys would leave the machine without a
    // keyboard. It only ever consumes Tab while Option is held, and that has held across
    // repeated sessions.
    //
    // Running indefinitely is not just convenience: MRU ordering is accumulated by watching
    // focus over time, so a switcher that only lives for two minutes has no history to
    // order by and cannot answer "the window I was in before".

    // Tracking has to start before the first gesture: ordering is accumulated from focus
    // changes over time, so history is empty until the user has switched around a little.
    let history = WindowHistory()
    let tracker = FocusTracker(history: history, report: report)
    tracker.start()

    let monitor = HotkeyMonitor(report: report, history: history)
    guard monitor.start() else {
        report.add("Could not install the event tap.")
        report.close()
        exit(1)
    }

    // Held in a binding: the status item lives only as long as this reference does, and
    // releasing it would silently remove the icon from the menu bar.
    let statusBar = StatusBarController(history: history, report: report)
    _ = statusBar

    report.add("Hold Option and press Tab to cycle. Release Option to switch.")
    report.add("Shift reverses direction, Escape cancels.")
    report.add("Quit from the menu bar icon, or: pkill -f AltTabClone")
    report.add()

    RunLoop.current.run()
    exit(0)
}

// MARK: - List

let windows = WindowEnumerator.allWindows()

report.add("Windows found: \(windows.count)")
report.add()
for (index, window) in windows.enumerated() {
    report.add(describe(window, index: index))
}

// MARK: - Raise

guard let flag = arguments.firstIndex(of: "--raise"),
      let index = arguments[safe: flag + 1].flatMap(Int.init) else {
    report.add()
    report.add("No --raise argument. Pass one to focus a window, e.g. --raise 0")
    report.close()
    exit(0)
}

guard let target = windows[safe: index] else {
    report.add()
    report.add("Index \(index) is out of range (0..<\(windows.count)).")
    report.close()
    exit(1)
}

report.add()
report.add("Frontmost before: \(NSWorkspace.shared.frontmostApplication?.localizedName ?? "unknown")")
report.add("Raising \(describe(target).trimmingCharacters(in: .whitespaces))")

let outcome = WindowRaiser.raise(target)
report.add("  markedMain: \(outcome.markedMain), raised: \(outcome.raised), activated: \(outcome.activated)")

pump(1.2)

// MARK: - Verify

report.add()
report.add("Frontmost after: \(NSWorkspace.shared.frontmostApplication?.localizedName ?? "unknown")")
report.add("App focus moved: \(NSWorkspace.shared.frontmostApplication?.processIdentifier == target.pid ? "YES" : "NO")")

// Re-read the tree: which of the target app's windows does it now consider main?
let siblings = WindowEnumerator.allWindows().filter { $0.pid == target.pid }
report.add()
report.add("Windows of \(target.appName) after raising (\(siblings.count)):")
for sibling in siblings {
    report.add(describe(sibling))
}

report.add()
let mainTitle = siblings.first(where: \.isMain)?.title
if mainTitle == target.title {
    report.add("RESULT: the requested window is now main.")
} else {
    report.add("RESULT: wrong window is main — wanted '\(target.title)', got '\(mainTitle ?? "none")'.")
}

report.close()
exit(0)
