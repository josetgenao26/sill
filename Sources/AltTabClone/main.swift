import AppKit
import Foundation

// Step 2 probe: prove a specific window can be raised and focused.
//
// Enumerating windows is only useful if focus can be moved to one of them, so this
// verifies the full path before any UI or hotkey handling is built.
//
//   open build/AltTabClone.app --args --raise 3
//
// Focus is checked twice after the raise: which app is frontmost, and which of that app's
// windows is now main. The second check is the one that matters — the whole premise of the
// project is switching between windows of the *same* app, which share a pid and are
// indistinguishable by the first check alone.

let arguments = CommandLine.arguments

// An accessory app has no Dock icon or menu bar but can still own windows, which is what
// a switcher needs. NSApplication must exist before any window or activation work.
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

report.add("Waiting for Accessibility permission...")

guard AX.waitForTrust(timeout: 300) else {
    report.add("Accessibility: DENIED (timed out)")
    report.add()
    report.add("Enable AltTabClone in System Settings > Privacy & Security > Accessibility.")
    report.add("If it is already enabled, the entry is stale from a rebuild: remove it with")
    report.add("the minus button and add it again.")
    report.close()
    exit(1)
}

report.add("Accessibility: granted")
report.add()

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

let previous = NSWorkspace.shared.frontmostApplication
report.add()
report.add("Frontmost before: \(previous?.localizedName ?? "unknown")")
report.add("Raising \(describe(target).trimmingCharacters(in: .whitespaces))")

let outcome = WindowRaiser.raise(target)
report.add("  markedMain: \(outcome.markedMain), raised: \(outcome.raised), activated: \(outcome.activated)")

pump(1.2)

// MARK: - Verify

let frontmost = NSWorkspace.shared.frontmostApplication
report.add()
report.add("Frontmost after: \(frontmost?.localizedName ?? "unknown")")

let appMatched = frontmost?.processIdentifier == target.pid
report.add("App focus moved: \(appMatched ? "YES" : "NO")")

// Re-read the tree: which of the target app's windows does it now consider main?
let siblings = WindowEnumerator.allWindows().filter { $0.pid == target.pid }
report.add()
report.add("Windows of \(target.appName) after raising (\(siblings.count)):")
for sibling in siblings {
    report.add(describe(sibling))
}

let mainTitle = siblings.first(where: \.isMain)?.title
report.add()
if mainTitle == target.title {
    report.add("RESULT: the requested window is now main.")
} else {
    report.add("RESULT: wrong window is main — wanted '\(target.title)', got '\(mainTitle ?? "none")'.")
}

report.close()
exit(0)
