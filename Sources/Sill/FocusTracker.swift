import AppKit
import ApplicationServices

/// Watches focus changes and feeds them to a `WindowHistory`.
///
/// Two sources are needed, because they report different events:
///
/// - `NSWorkspace.didActivateApplicationNotification` fires when the focused *app*
///   changes. It says nothing about which of that app's windows is now focused.
/// - `kAXFocusedWindowChangedNotification` fires when the focused *window* changes inside
///   one app. Without it, switching between two windows of the same app is invisible —
///   and that is the case the whole project exists to handle.
final class FocusTracker {
    private let history: WindowHistory
    private let report: Report

    /// Observers are retained per pid. An AXObserver stops delivering once released, and
    /// the run loop source alone does not keep it alive.
    private var observers: [pid_t: AXObserver] = [:]

    init(history: WindowHistory, report: Report) {
        self.history = history
        self.report = report
    }

    func start() {
        let workspace = NSWorkspace.shared

        workspace.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let key = NSWorkspace.applicationUserInfoKey
            guard let app = notification.userInfo?[key] as? NSRunningApplication else { return }
            self?.recordFocusedWindow(of: app.processIdentifier)
            self?.observe(app)
        }

        // Seed from the apps already running, and record the current window so the very
        // first switch has something to go back to.
        for app in workspace.runningApplications where app.activationPolicy == .regular {
            observe(app)
        }
        if let active = workspace.frontmostApplication {
            recordFocusedWindow(of: active.processIdentifier)
        }
    }

    // MARK: - Per-app window focus

    private func observe(_ app: NSRunningApplication) {
        let pid = app.processIdentifier
        guard observers[pid] == nil else { return }

        var observer: AXObserver?
        let callback: AXObserverCallback = { _, element, _, refcon in
            guard let refcon else { return }
            // Like the event tap callback, this is a C function pointer and cannot
            // capture context, so the instance travels through refcon.
            let tracker = Unmanaged<FocusTracker>.fromOpaque(refcon).takeUnretainedValue()
            tracker.history.recordFocus(element)
        }

        guard AXObserverCreate(pid, callback, &observer) == .success, let observer else { return }

        let axApp = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(axApp, 0.25)

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for name in [kAXFocusedWindowChangedNotification, kAXMainWindowChangedNotification] {
            AXObserverAddNotification(observer, axApp, name as CFString, refcon)
        }

        CFRunLoopAddSource(
            CFRunLoopGetCurrent(),
            AXObserverGetRunLoopSource(observer),
            .commonModes
        )
        observers[pid] = observer
    }

    /// Reads an app's currently focused window and records it.
    ///
    /// App activation says which app has focus but not which of its windows, so the
    /// window has to be read back explicitly.
    private func recordFocusedWindow(of pid: pid_t) {
        let axApp = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(axApp, 0.25)
        guard let window: AXUIElement = AX.attribute(axApp, kAXFocusedWindowAttribute as String) else {
            return
        }
        history.recordFocus(window)
    }
}
