import AppKit

/// The floating list the user sees while cycling.
///
/// The panel must never take focus. If it did, this app would become the most recently
/// used one, so "the previous window" would become the switcher itself and the ordering
/// would be corrupted by its own UI. That constraint drives every window setting here:
/// `.nonactivatingPanel`, `orderFrontRegardless()` rather than `makeKeyAndOrderFront()`,
/// and `becomesKeyOnlyIfNeeded`.
final class SwitcherPanel {
    private enum Metrics {
        static let rowHeight: CGFloat = 44
        static let iconSize: CGFloat = 28
        static let width: CGFloat = 520
        static let padding: CGFloat = 12
        static let cornerRadius: CGFloat = 14
        static let maxVisibleRows = 12
    }

    private var panel: NSPanel?
    private var rows: [RowView] = []
    private var iconCache: [pid_t: NSImage?] = [:]

    // MARK: - Presentation

    func show(_ windows: [WindowInfo], selection: Int) {
        let panel = panel ?? makePanel()
        self.panel = panel

        let visible = Array(windows.prefix(Metrics.maxVisibleRows))
        rebuild(panel: panel, windows: visible)
        highlight(selection)

        let height = CGFloat(visible.count) * Metrics.rowHeight + Metrics.padding * 2
        let size = NSSize(width: Metrics.width, height: height)

        // Centred on whichever screen holds the pointer: with several displays, the one
        // being looked at is the one the pointer is on.
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }
            ?? NSScreen.main
        if let frame = screen?.frame {
            panel.setFrame(
                NSRect(
                    x: frame.midX - size.width / 2,
                    y: frame.midY - size.height / 2,
                    width: size.width,
                    height: size.height
                ),
                display: false
            )
        }

        // orderFrontRegardless shows the panel without asking for focus, which
        // makeKeyAndOrderFront would do.
        panel.orderFrontRegardless()
    }

    func highlight(_ selection: Int) {
        for (index, row) in rows.enumerated() {
            row.isSelected = index == selection
        }
    }

    func hide() {
        panel?.orderOut(nil)
    }

    // MARK: - Construction

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: Metrics.width, height: Metrics.rowHeight),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )

        // Above normal and floating windows, so the switcher is not hidden by whatever
        // the user is switching away from.
        panel.level = .popUpMenu
        // Without .canJoinAllSpaces and .fullScreenAuxiliary the panel does not appear
        // over full-screen apps — precisely where a switcher is most needed.
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        // Selection is keyboard-driven; letting clicks through avoids interfering with
        // whatever is underneath.
        panel.ignoresMouseEvents = true

        let background = NSVisualEffectView()
        background.material = .hudWindow
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = Metrics.cornerRadius
        background.layer?.masksToBounds = true
        panel.contentView = background

        return panel
    }

    /// Rebuilds the rows only when the window list actually differs, so that cycling
    /// through a stable list just moves the highlight.
    private func rebuild(panel: NSPanel, windows: [WindowInfo]) {
        let unchanged = rows.count == windows.count
            && zip(rows, windows).allSatisfy { $0.0.matches($0.1) }
        guard !unchanged else { return }

        panel.contentView?.subviews.forEach { $0.removeFromSuperview() }
        rows = windows.map { window in
            RowView(window: window, icon: icon(for: window.pid))
        }

        let stack = NSStackView(views: rows)
        stack.orientation = .vertical
        stack.spacing = 0
        stack.alignment = .leading
        stack.distribution = .fillEqually
        stack.translatesAutoresizingMaskIntoConstraints = false

        guard let content = panel.contentView else { return }
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: Metrics.padding),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -Metrics.padding),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: Metrics.padding),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -Metrics.padding),
        ])
    }

    /// Icons are looked up per process and cached: a switcher redraws on every keystroke,
    /// and `NSRunningApplication.icon` is not cheap enough to call at that rate.
    private func icon(for pid: pid_t) -> NSImage? {
        if let cached = iconCache[pid] { return cached }
        let icon = NSRunningApplication(processIdentifier: pid)?.icon
        iconCache[pid] = icon
        return icon
    }

    // MARK: - Row

    private final class RowView: NSView {
        private let pid: pid_t
        private let title: String
        private let label = NSTextField(labelWithString: "")

        var isSelected = false {
            didSet { needsDisplay = true }
        }

        init(window: WindowInfo, icon: NSImage?) {
            self.pid = window.pid
            self.title = window.title
            super.init(frame: .zero)

            wantsLayer = true
            translatesAutoresizingMaskIntoConstraints = false
            heightAnchor.constraint(equalToConstant: Metrics.rowHeight).isActive = true

            let imageView = NSImageView(image: icon ?? NSImage())
            imageView.translatesAutoresizingMaskIntoConstraints = false

            let displayTitle = window.title.isEmpty ? "(untitled)" : window.title
            label.stringValue = "\(window.appName) — \(displayTitle)"
            label.lineBreakMode = .byTruncatingMiddle
            label.font = .systemFont(ofSize: 13)
            label.translatesAutoresizingMaskIntoConstraints = false

            addSubview(imageView)
            addSubview(label)

            NSLayoutConstraint.activate([
                imageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
                imageView.centerYAnchor.constraint(equalTo: centerYAnchor),
                imageView.widthAnchor.constraint(equalToConstant: Metrics.iconSize),
                imageView.heightAnchor.constraint(equalToConstant: Metrics.iconSize),

                label.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 10),
                label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
                label.centerYAnchor.constraint(equalTo: centerYAnchor),
            ])
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("not used") }

        func matches(_ window: WindowInfo) -> Bool {
            window.pid == pid && window.title == title
        }

        override func draw(_ dirtyRect: NSRect) {
            guard isSelected else { return }
            NSColor.selectedContentBackgroundColor.withAlphaComponent(0.85).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8).fill()
        }
    }
}
