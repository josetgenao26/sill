import AppKit
import Foundation

// Entry point. One mode runs the switcher; the other two remain as probes, because being
// able to test enumeration and raising in isolation is what made each layer debuggable.
//
//   open build/Sill.app --args --hotkey     run the switcher
//   open build/Sill.app                     list windows, then exit
//   open build/Sill.app --args --raise 3    raise one window by index

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
    report.add("Enable Sill in System Settings > Privacy & Security > Accessibility.")
    report.close()
    exit(1)
}

// MARK: - Hotkey mode

if arguments.contains("--hotkey") || arguments.contains("--demo") {
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

    let thumbnails = ThumbnailProvider(report: report)
    let monitor = HotkeyMonitor(report: report, history: history, thumbnails: thumbnails)
    guard monitor.start() else {
        report.add("Could not install the event tap.")
        report.close()
        exit(1)
    }

    let statusBar = StatusBarController(history: history, report: report)

    report.add("Hold Option and press Tab to cycle. Release Option to switch.")
    report.add("Shift reverses direction, Escape cancels.")
    report.add("Quit from the menu bar icon, or: pkill -f Sill")
    report.add()

    // --demo holds the panel open with no gesture, so it can be photographed: the panel
    // normally exists only while the modifier is held, and every screenshot shortcut needs
    // modifiers of its own.
    //
    // It runs *inside* the switcher rather than as a separate mode. As its own mode it
    // exited when the timer ran out, which quietly killed the running switcher along with
    // it — a screenshot session left the user with no switcher and no clue why.
    if let flag = arguments.firstIndex(of: "--demo") {
        let seconds = arguments[safe: flag + 1].flatMap(Double.init) ?? 20
        monitor.showDemoPanel(seconds: seconds)
    }

    // ARC ends an object's life after its last use, not at the end of its lexical scope.
    // These three are never referenced again — the tap and the observers call into them
    // from C callbacks that deliberately hold no reference — so without an explicit
    // lifetime the optimiser is free to release them before the run loop even starts.
    withExtendedLifetime((statusBar, monitor, tracker)) {
        // NSApplication.run(), not RunLoop.run(). A bare run loop pumps run loop *sources*,
        // which is enough for the event tap and the AX observers, so the switcher works and
        // the menu bar icon even draws. But AppKit's UI event dispatch lives in
        // NSApplication's own loop: without it a click on the status item is never
        // delivered to anything, and the menu silently refuses to open.
        application.run()
    }
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
