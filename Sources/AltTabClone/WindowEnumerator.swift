import AppKit
import ApplicationServices

/// A single switchable window discovered through the Accessibility API.
struct WindowInfo {
    let appName: String
    let pid: pid_t
    let title: String
    let frame: CGRect
    let isMinimized: Bool

    /// Live handle to the window. Kept so a later step can raise it; it is only valid
    /// while the owning process is alive.
    let element: AXUIElement
}

/// Discovers the windows a user could plausibly switch to.
///
/// This deliberately uses the Accessibility API rather than `CGWindowListCopyWindowInfo`.
/// The CGWindowList route can enumerate windows too, but it hands back inert metadata:
/// there is no way to raise a window from it. AX elements are live handles that support
/// `kAXRaiseAction`, which is what the switcher will ultimately need.
enum WindowEnumerator {
    static func allWindows() -> [WindowInfo] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }  // skip agents and daemons: no user-facing windows
            .flatMap(windows(of:))
    }

    private static func windows(of app: NSRunningApplication) -> [WindowInfo] {
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        guard let windows: [AXUIElement] = AX.attribute(axApp, kAXWindowsAttribute as String) else {
            // Normal, not an error: apps with no open windows, and apps that expose no
            // AX tree at all (some Electron/Java/X11 hosts), both land here.
            return []
        }
        let appName = app.localizedName ?? "Unknown"
        return windows.compactMap { window in
            guard let frame = AX.frame(of: window) else { return nil }
            return WindowInfo(
                appName: appName,
                pid: app.processIdentifier,
                title: AX.attribute(window, kAXTitleAttribute as String) ?? "",
                frame: frame,
                isMinimized: AX.attribute(window, kAXMinimizedAttribute as String) ?? false,
                element: window
            )
        }
    }
}
