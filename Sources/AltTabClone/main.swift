import Foundation

// Step 1 probe: prove the Accessibility tree returns the windows we expect,
// before any UI, hotkey handling, or thumbnail capture is built on top of it.

guard AX.isTrusted(prompt: true) else {
    FileHandle.standardError.write(Data("""
        Accessibility permission is required.

        Grant it in System Settings > Privacy & Security > Accessibility,
        then run this again.

        """.utf8))
    exit(1)
}

let windows = WindowEnumerator.allWindows()

guard !windows.isEmpty else {
    print("No windows found. Permission is granted, so this means no regular app has an open window.")
    exit(0)
}

print("Found \(windows.count) window(s):\n")
for window in windows {
    let title = window.title.isEmpty ? "(untitled)" : window.title
    let state = window.isMinimized ? " [minimized]" : ""
    let size = "\(Int(window.frame.width))x\(Int(window.frame.height))"
    print("  \(window.appName) — \(title)\(state)  \(size)  pid:\(window.pid)")
}
