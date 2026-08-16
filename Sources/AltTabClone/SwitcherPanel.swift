import AppKit

/// Anything the panel can highlight, so selection handling does not care which layout is
/// on screen.
private protocol SelectableView: NSView {
    var isSelected: Bool { get set }
    func matches(_ window: WindowInfo) -> Bool
}

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
        static let listWidth: CGFloat = 520
        static let iconSize: CGFloat = 28

        static let cellWidth: CGFloat = 168
        static let cellHeight: CGFloat = 132
        static let columns = 5

        static let padding: CGFloat = 12
        static let cornerRadius: CGFloat = 14
        static let maxVisible = 15
    }

    private var panel: NSPanel?
    private var cells: [SelectableView] = []
    private var iconCache: [pid_t: NSImage?] = [:]
    private var layout: PanelLayout = .list

    // MARK: - Presentation

    func show(_ windows: [WindowInfo], selection: Int, layout: PanelLayout, thumbnails: ThumbnailProvider?) {
        let panel = panel ?? makePanel()
        self.panel = panel
        self.layout = layout

        let visible = Array(windows.prefix(Metrics.maxVisible))
        rebuild(panel: panel, windows: visible, thumbnails: thumbnails)
        highlight(selection)
        resize(panel: panel, count: visible.count)

        // orderFrontRegardless shows the panel without asking for focus, which
        // makeKeyAndOrderFront would do.
        panel.orderFrontRegardless()
    }

    func highlight(_ selection: Int) {
        for (index, cell) in cells.enumerated() {
            cell.isSelected = index == selection
        }
    }

    /// Fills in a preview that arrived after the panel was already on screen.
    func setThumbnail(_ image: NSImage, for key: ThumbnailProvider.Key) {
        for case let cell as ThumbnailCell in cells where cell.key == key {
            cell.setImage(image)
        }
    }

    func hide() {
        panel?.orderOut(nil)
    }

    // MARK: - Geometry

    private func resize(panel: NSPanel, count: Int) {
        let size: NSSize
        switch layout {
        case .list:
            size = NSSize(
                width: Metrics.listWidth,
                height: CGFloat(count) * Metrics.rowHeight + Metrics.padding * 2
            )
        case .thumbnails:
            let columns = min(count, Metrics.columns)
            let rows = Int(ceil(Double(count) / Double(Metrics.columns)))
            size = NSSize(
                width: CGFloat(columns) * Metrics.cellWidth + Metrics.padding * 2,
                height: CGFloat(rows) * Metrics.cellHeight + Metrics.padding * 2
            )
        }

        // Centred on whichever screen holds the pointer: with several displays, the one
        // being looked at is the one the pointer is on.
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }
            ?? NSScreen.main
        guard let frame = screen?.frame else { return }
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

    // MARK: - Construction

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: Metrics.listWidth, height: Metrics.rowHeight),
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

    /// Rebuilds only when the window list actually differs, so that cycling through a
    /// stable list just moves the highlight.
    private func rebuild(panel: NSPanel, windows: [WindowInfo], thumbnails: ThumbnailProvider?) {
        let unchanged = cells.count == windows.count
            && zip(cells, windows).allSatisfy { $0.0.matches($0.1) }
        guard !unchanged else { return }

        panel.contentView?.subviews.forEach { $0.removeFromSuperview() }

        let container: NSView
        switch layout {
        case .list:
            cells = windows.map { ListRow(window: $0, icon: icon(for: $0.pid)) }
            container = verticalStack(cells)
        case .thumbnails:
            cells = windows.map {
                ThumbnailCell(
                    window: $0,
                    icon: icon(for: $0.pid),
                    preview: thumbnails?.cached(for: $0)
                )
            }
            container = grid(cells)
        }

        guard let content = panel.contentView else { return }
        container.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(container)
        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: Metrics.padding),
            container.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -Metrics.padding),
            container.topAnchor.constraint(equalTo: content.topAnchor, constant: Metrics.padding),
            container.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -Metrics.padding),
        ])
    }

    private func verticalStack(_ views: [NSView]) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.spacing = 0
        stack.alignment = .leading
        stack.distribution = .fillEqually
        return stack
    }

    private func grid(_ views: [NSView]) -> NSStackView {
        let rows = stride(from: 0, to: views.count, by: Metrics.columns).map { start -> NSStackView in
            let slice = Array(views[start..<min(start + Metrics.columns, views.count)])
            let row = NSStackView(views: slice)
            row.orientation = .horizontal
            row.spacing = 0
            row.alignment = .top
            return row
        }
        let stack = NSStackView(views: rows)
        stack.orientation = .vertical
        stack.spacing = 0
        stack.alignment = .leading
        return stack
    }

    /// Icons are looked up per process and cached: a switcher redraws on every keystroke,
    /// and `NSRunningApplication.icon` is not cheap enough to call at that rate.
    private func icon(for pid: pid_t) -> NSImage? {
        if let cached = iconCache[pid] { return cached }
        let icon = NSRunningApplication(processIdentifier: pid)?.icon
        iconCache[pid] = icon
        return icon
    }

    // MARK: - List row

    private final class ListRow: NSView, SelectableView {
        private let pid: pid_t
        private let title: String

        var isSelected = false {
            didSet { needsDisplay = true }
        }

        init(window: WindowInfo, icon: NSImage?) {
            pid = window.pid
            title = window.title
            super.init(frame: .zero)

            wantsLayer = true
            translatesAutoresizingMaskIntoConstraints = false
            heightAnchor.constraint(equalToConstant: Metrics.rowHeight).isActive = true

            let imageView = NSImageView(image: icon ?? NSImage())
            imageView.translatesAutoresizingMaskIntoConstraints = false

            let label = NSTextField(labelWithString: "\(window.appName) — \(window.displayTitle)")
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

    // MARK: - Thumbnail cell

    private final class ThumbnailCell: NSView, SelectableView {
        let key: ThumbnailProvider.Key
        private let preview = NSImageView()
        private let badge: NSImageView

        var isSelected = false {
            didSet { needsDisplay = true }
        }

        init(window: WindowInfo, icon: NSImage?, preview image: NSImage?) {
            key = ThumbnailProvider.Key(window)
            badge = NSImageView(image: icon ?? NSImage())
            super.init(frame: .zero)

            wantsLayer = true
            translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                widthAnchor.constraint(equalToConstant: Metrics.cellWidth),
                heightAnchor.constraint(equalToConstant: Metrics.cellHeight),
            ])

            // Falls back to the app icon until the capture arrives, so the panel is never
            // a grid of empty boxes while ScreenCaptureKit works.
            preview.image = image ?? icon
            preview.imageScaling = .scaleProportionallyUpOrDown
            preview.translatesAutoresizingMaskIntoConstraints = false
            badge.translatesAutoresizingMaskIntoConstraints = false

            let label = NSTextField(labelWithString: window.displayTitle)
            label.lineBreakMode = .byTruncatingTail
            label.alignment = .center
            label.font = .systemFont(ofSize: 11)
            label.textColor = .secondaryLabelColor
            label.translatesAutoresizingMaskIntoConstraints = false

            addSubview(preview)
            addSubview(badge)
            addSubview(label)

            NSLayoutConstraint.activate([
                preview.topAnchor.constraint(equalTo: topAnchor, constant: 10),
                preview.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
                preview.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
                preview.heightAnchor.constraint(equalToConstant: 86),

                // Overlaid on the preview: which app a window belongs to is not always
                // obvious from its contents alone.
                badge.trailingAnchor.constraint(equalTo: preview.trailingAnchor),
                badge.bottomAnchor.constraint(equalTo: preview.bottomAnchor),
                badge.widthAnchor.constraint(equalToConstant: 22),
                badge.heightAnchor.constraint(equalToConstant: 22),

                label.topAnchor.constraint(equalTo: preview.bottomAnchor, constant: 4),
                label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
                label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            ])
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("not used") }

        func setImage(_ image: NSImage) {
            preview.image = image
        }

        func matches(_ window: WindowInfo) -> Bool {
            ThumbnailProvider.Key(window) == key
        }

        override func draw(_ dirtyRect: NSRect) {
            guard isSelected else { return }
            NSColor.selectedContentBackgroundColor.withAlphaComponent(0.85).setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 4, dy: 4), xRadius: 10, yRadius: 10).fill()
        }
    }
}

extension WindowInfo {
    var displayTitle: String {
        title.isEmpty ? "(untitled)" : title
    }
}
