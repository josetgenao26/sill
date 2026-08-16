import AppKit
import ServiceManagement

/// The menu bar presence: a visible sign the switcher is running, and a way to quit it
/// without hunting for the process.
///
/// This is the only user interface the app has outside the switcher panel. An accessory
/// app has no Dock icon and no menu bar of its own, so without a status item a running
/// switcher is indistinguishable from a crashed one.
final class StatusBarController: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let history: WindowHistory
    private let report: Report

    private let windowCountItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let loginItem = NSMenuItem(
        title: "Start at Login",
        action: #selector(toggleLaunchAtLogin),
        keyEquivalent: ""
    )

    init(history: WindowHistory, report: Report) {
        self.history = history
        self.report = report
        super.init()

        let icon = NSImage(systemSymbolName: "square.stack", accessibilityDescription: "AltTabClone")
        item.button?.image = icon
        item.button?.imagePosition = .imageLeading

        // Carries a text label as well as the icon. A button with neither has zero width —
        // present in the menu bar but invisible and unclickable — and on a crowded or
        // notched menu bar a narrow icon-only item is easy to lose entirely.
        item.button?.title = " ATC"

        // Lets macOS remember where the user put this item between launches, so it does
        // not reappear in a different slot after every rebuild.
        item.autosaveName = "AltTabCloneStatusItem"

        report.add("status item — button: \(item.button != nil), icon: \(icon != nil)")

        let menu = NSMenu()
        menu.delegate = self

        windowCountItem.isEnabled = false
        menu.addItem(windowCountItem)
        menu.addItem(.separator())

        loginItem.target = self
        menu.addItem(loginItem)
        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit AltTabClone", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        item.menu = menu
    }

    // MARK: - NSMenuDelegate

    /// Counts are read when the menu opens rather than kept live: enumerating windows
    /// costs synchronous calls into every running app, which is not something to do on a
    /// timer for a label nobody is looking at.
    func menuWillOpen(_ menu: NSMenu) {
        report.add("menu opened")
        let count = WindowEnumerator.allWindows().count
        windowCountItem.title = "\(count) window\(count == 1 ? "" : "s")"
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    // MARK: - Actions

    @objc private func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
                report.add("launch at login: disabled")
            } else {
                try service.register()
                report.add("launch at login: enabled")
            }
        } catch {
            // Registration refuses for bundles in unusual locations, which a build
            // directory certainly is. Surfacing it beats failing silently.
            report.add("launch at login failed: \(error.localizedDescription)")
        }
    }

    @objc private func quit() {
        report.add("quit from menu bar")
        report.close()
        NSApplication.shared.terminate(nil)
    }
}
