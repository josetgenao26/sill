import Foundation

// Step 1 probe: prove the Accessibility tree returns the windows we expect,
// before any UI, hotkey handling, or thumbnail capture is built on top of it.

let report = Report()
defer { report.close() }

report.add("Waiting for Accessibility permission...")

guard AX.waitForTrust(timeout: 90) else {
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

// Progress is logged per app so that a hang points at the app responsible for it.
let windows = WindowEnumerator.allWindows { appName in
    report.add("  querying \(appName)...")
}

report.add()
report.add("Windows found: \(windows.count)")
report.add()

for window in windows {
    let title = window.title.isEmpty ? "(untitled)" : window.title
    let state = window.isMinimized ? " [minimized]" : ""
    let size = "\(Int(window.frame.width))x\(Int(window.frame.height))"
    report.add("  \(window.appName) — \(title)\(state)  \(size)  pid:\(window.pid)")
}

report.close()
