import AppKit
import ApplicationServices

/// A single switchable window discovered through the Accessibility API.
struct WindowInfo {
    let appName: String
    let pid: pid_t
    let title: String
    let frame: CGRect
    let isMinimized: Bool

    /// Whether the owning app considers this its main window. For an app with several
    /// windows this is the only way to tell *which* one focus landed on, since they all
    /// share a pid.
    let isMain: Bool

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
    /// Longest wait for any single Accessibility call, in seconds.
    ///
    /// Accessibility calls are synchronous IPC into the target process. An app that is
    /// busy, beachballing, or stopped in a debugger will never answer, and the default
    /// behaviour is to wait forever — one stuck app would hang the whole switcher.
    /// Dropping that app from the list is far better than freezing.
    ///
    /// The timeout is set on every element, not just the application element. Window
    /// elements returned by a query are separate references that otherwise fall back to
    /// the default, so setting it once on the app is not enough.
    private static let messagingTimeout: Float = 0.25

    /// Enumerates windows, reporting progress per app.
    ///
    /// `onProgress` fires before each app is queried so a hang is attributable to a
    /// specific app in the log rather than showing up as silence.
    static func allWindows(onProgress: (String) -> Void = { _ in }) -> [WindowInfo] {
        let ownPid = ProcessInfo.processInfo.processIdentifier

        return NSWorkspace.shared.runningApplications
            .filter {
                // Agents and daemons have no user-facing windows. This app is an agent
                // too, but its settings window is a real window a user may want to switch
                // back to — the switcher panel itself is excluded by the standard-window
                // subrole check below, since a borderless panel is not a standard window.
                $0.activationPolicy == .regular || $0.processIdentifier == ownPid
            }
            .flatMap { app -> [WindowInfo] in
                onProgress(app.localizedName ?? "pid \(app.processIdentifier)")
                return windows(of: app)
            }
    }

    private static func windows(of app: NSRunningApplication) -> [WindowInfo] {
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(axApp, messagingTimeout)

        guard let windows: [AXUIElement] = AX.attribute(axApp, kAXWindowsAttribute as String) else {
            // Normal, not an error: apps with no open windows, apps that time out, and
            // apps that expose no AX tree at all (some Electron/Java/X11 hosts) all land here.
            return []
        }

        let appName = app.localizedName ?? "Unknown"
        return windows.compactMap { window in
            AXUIElementSetMessagingTimeout(window, messagingTimeout)

            // Only real, switchable windows. The clearest case this removes is Finder's
            // desktop window, which enumerates like any other window but refuses
            // kAXRaiseAction — it was silently occupying a slot in the list and doing
            // nothing when selected. Sheets, popovers and drawers fail the same check.
            guard AX.attribute(window, kAXSubroleAttribute as String) == kAXStandardWindowSubrole else {
                return nil
            }

            guard let frame = AX.frame(of: window) else { return nil }
            return WindowInfo(
                appName: appName,
                pid: app.processIdentifier,
                title: AX.attribute(window, kAXTitleAttribute as String) ?? "",
                frame: frame,
                isMinimized: AX.attribute(window, kAXMinimizedAttribute as String) ?? false,
                isMain: AX.attribute(window, kAXMainAttribute as String) ?? false,
                element: window
            )
        }
    }
}
