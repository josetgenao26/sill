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

    /// Layout is also offered here, not only in settings: switching between reading titles
    /// and recognising previews is a per-moment decision, and making it a trip through a
    /// settings window would put friction on the one setting people flip most.
    private let layoutItems: [NSMenuItem] = PanelLayout.allCases.map {
        NSMenuItem(title: $0.label, action: #selector(chooseLayout(_:)), keyEquivalent: "")
    }

    private let settings = SettingsWindow()

    init(history: WindowHistory, report: Report) {
        self.history = history
        self.report = report
        super.init()

        // A PDF rather than a PNG so macOS rasterises it per display scale, and marked as a
        // template so the system tints it — black on a light menu bar, white on a dark one.
        // Without isTemplate the mark would stay black and vanish in dark mode.
        let icon = Bundle.main.url(forResource: "menubar-template", withExtension: "pdf")
            .flatMap { NSImage(contentsOf: $0) }
            ?? NSImage(systemSymbolName: "square.stack", accessibilityDescription: "Sill")
        icon?.isTemplate = true
        icon?.size = NSSize(width: 16, height: 16)
        item.button?.image = icon

        // A button with neither image nor title has zero width: present in the menu bar,
        // but invisible and unclickable. Keeping a title as well would only be noise now
        // that there is a real mark, so the fallback covers the icon failing to load.
        if icon == nil {
            item.button?.title = "Sill"
        }

        // Lets macOS remember where the user put this item between launches, so it does
        // not reappear in a different slot after every rebuild.
        item.autosaveName = "SillStatusItem"

        report.add("status item — button: \(item.button != nil), icon: \(icon != nil)")

        let menu = NSMenu()
        menu.delegate = self

        windowCountItem.isEnabled = false
        menu.addItem(windowCountItem)
        menu.addItem(.separator())

        for item in layoutItems {
            item.target = self
            menu.addItem(item)
        }

        menu.addItem(.separator())

        loginItem.target = self
        menu.addItem(loginItem)

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit Sill", action: #selector(quit), keyEquivalent: "q")
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

        let layout = Preferences.layout
        for (item, candidate) in zip(layoutItems, PanelLayout.allCases) {
            item.state = candidate == layout ? .on : .off
        }
    }

    // MARK: - Actions

    @objc private func chooseLayout(_ sender: NSMenuItem) {
        guard let position = layoutItems.firstIndex(of: sender) else { return }
        let layout = PanelLayout.allCases[position]
        Preferences.layout = layout
        report.add("layout: \(layout.rawValue)")

        // Screen recording is only needed for captures, so it is requested when the user
        // asks for a layout that uses them rather than at launch. Unlike Accessibility
        // this cannot be polled — the prompt appears once and the user has to act on it.
        if layout.needsCapture, !ThumbnailProvider.hasPermission() {
            report.add("screen recording not granted — prompting")
            ThumbnailProvider.requestPermission()
        }
    }

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

    @objc private func openSettings() {
        settings.show()
    }

    @objc private func quit() {
        report.add("quit from menu bar")
        report.close()
        NSApplication.shared.terminate(nil)
    }
}
