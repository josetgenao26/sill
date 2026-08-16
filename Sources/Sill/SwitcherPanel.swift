import AppKit

/// Anything the panel can highlight, so selection handling does not care which layout is
/// on screen.
private protocol SelectableView: NSView {
    var isSelected: Bool { get set }
    var index: Int { get set }
    var onHover: ((Int) -> Void)? { get set }
    var onClick: ((Int) -> Void)? { get set }
    func matches(_ window: WindowInfo) -> Bool
}

/// Hover and click handling shared by both layouts.
///
/// The tracking area is `.activeAlways` on purpose. This app is never the active
/// application — that is the constraint the whole switcher is built around — so the
/// default tracking modes, which require an active app or key window, would never fire.
private extension NSView {
    func installTracking() {
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self
        ))
    }
}

/// The floating list the user sees while cycling.
///
/// The panel must never take focus. If it did, this app would become the most recently
/// used one, so "the previous window" would become the switcher itself and the ordering
/// would be corrupted by its own UI. That constraint drives every window setting here:
/// `.nonactivatingPanel`, `orderFrontRegardless()` rather than `makeKeyAndOrderFront()`,
/// and `becomesKeyOnlyIfNeeded`.
final class SwitcherPanel {
    /// Base geometry, scaled by the size preference.
    ///
    /// Read fresh through `current` rather than stored, so a size change takes effect on
    /// the next gesture without any plumbing to push it through the view tree.
    private struct Metrics {
        let scale: CGFloat

        static var current: Metrics { Metrics(scale: Preferences.size.scale) }

        var rowHeight: CGFloat { 44 * scale }
        var listWidth: CGFloat { 520 * scale }
        var iconSize: CGFloat { 28 * scale }

        var cellWidth: CGFloat { 168 * scale }
        var cellHeight: CGFloat { 132 * scale }
        var previewHeight: CGFloat { 86 * scale }
        var badgeSize: CGFloat { 22 * scale }

        var iconCellWidth: CGFloat { 104 * scale }
        var iconCellHeight: CGFloat { 104 * scale }
        var largeIconSize: CGFloat { 56 * scale }

        var padding: CGFloat { 12 * scale }
        var cornerRadius: CGFloat { 14 * scale }

        /// Icon cells are far narrower than previews, so they fit more per row before the
        /// panel grows wider than it is comfortable to scan.
        func columns(for layout: PanelLayout) -> Int {
            layout == .appIcons ? 8 : 5
        }

        func cellSize(for layout: PanelLayout) -> NSSize {
            layout == .appIcons
                ? NSSize(width: iconCellWidth, height: iconCellHeight)
                : NSSize(width: cellWidth, height: cellHeight)
        }
    }

    private var panel: NSPanel?
    private var cells: [SelectableView] = []
    private var iconCache: [pid_t: NSImage?] = [:]
    private var layout: PanelLayout = .list

    /// Pointing at an entry selects it, so releasing Option commits whatever is under the
    /// cursor — the same gesture as the keyboard path, just aimed differently.
    var onHover: ((Int) -> Void)?

    /// Clicking commits immediately, without waiting for Option to be released.
    var onClick: ((Int) -> Void)?

    init() {
        NotificationCenter.default.addObserver(
            forName: Preferences.didChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // Views and the panel itself are built from the metrics in force at the time.
            // Rebuilding is normally triggered by the window list changing, which a
            // settings change does not do — so a new size would otherwise not appear until
            // the user happened to open or close a window.
            self?.panel?.orderOut(nil)
            self?.panel = nil
            self?.cells = []
        }
    }

    // MARK: - Presentation

    func show(_ windows: [WindowInfo], selection: Int, layout: PanelLayout, thumbnails: ThumbnailProvider?) {
        let panel = panel ?? makePanel()
        self.panel = panel
        self.layout = layout

        let visible = Array(windows.prefix(Preferences.maxWindows))
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
                width: Metrics.current.listWidth,
                height: CGFloat(count) * Metrics.current.rowHeight + Metrics.current.padding * 2
            )
        case .thumbnails, .appIcons:
            let metrics = Metrics.current
            let perRow = metrics.columns(for: layout)
            let cell = metrics.cellSize(for: layout)
            size = NSSize(
                width: CGFloat(min(count, perRow)) * cell.width + metrics.padding * 2,
                height: CGFloat(Int(ceil(Double(count) / Double(perRow)))) * cell.height + metrics.padding * 2
            )
        }

        let screen: NSScreen?
        switch Preferences.screen {
        case .pointer:
            // With several displays, the one being looked at is the one the pointer is on.
            screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }
                ?? NSScreen.main
        case .main:
            screen = NSScreen.main
        }
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
            contentRect: NSRect(x: 0, y: 0, width: Metrics.current.listWidth, height: Metrics.current.rowHeight),
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
        // The panel accepts the mouse. Clicking a .nonactivatingPanel does not activate
        // this app, so pointing at a window costs nothing in ordering — and when the
        // window you want is visible, being made to Tab to it is pure friction.
        panel.ignoresMouseEvents = false

        let background = NSVisualEffectView()
        background.material = .hudWindow
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = Metrics.current.cornerRadius
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
        case .appIcons:
            cells = windows.map { IconCell(window: $0, icon: icon(for: $0.pid)) }
            container = grid(cells)
        }

        for (position, cell) in cells.enumerated() {
            cell.index = position
            cell.onHover = { [weak self] in self?.onHover?($0) }
            cell.onClick = { [weak self] in self?.onClick?($0) }
        }

        guard let content = panel.contentView else { return }
        container.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(container)
        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: Metrics.current.padding),
            container.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -Metrics.current.padding),
            container.topAnchor.constraint(equalTo: content.topAnchor, constant: Metrics.current.padding),
            container.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -Metrics.current.padding),
        ])
    }

    private func verticalStack(_ views: [NSView]) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.spacing = 0
        stack.alignment = .leading

        // Each row is tied to the stack's width explicitly rather than relying on the
        // stack's own alignment to stretch them. Leading alignment alone sized every row
        // to its own title, which cut the highlight and the click target short; .width
        // alignment stretched them but left where the content sat inside ambiguous.
        // A direct constraint says exactly one thing.
        //
        // No distribution is set: every row already carries a fixed height, and asking the
        // stack to distribute them as well would be two rules for one measurement.
        for view in views {
            view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        return stack
    }

    private func grid(_ views: [NSView]) -> NSStackView {
        let perRow = Metrics.current.columns(for: layout)
        let rows = stride(from: 0, to: views.count, by: perRow).map { start -> NSStackView in
            let slice = Array(views[start..<min(start + perRow, views.count)])
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

    // MARK: - Cells

    /// Selection, hover and click behave identically in every layout, so they live here
    /// rather than being repeated three times with three chances to drift apart.
    private class Cell: NSView, SelectableView {
        var index = 0
        var onHover: ((Int) -> Void)?
        var onClick: ((Int) -> Void)?

        var isSelected = false {
            didSet { needsDisplay = true }
        }

        /// How far the selection highlight is inset, and how round it is. Rows fill their
        /// width; grid cells need breathing room so neighbouring highlights do not touch.
        var highlightInset: CGFloat { 0 }
        var highlightRadius: CGFloat { 8 }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            installTracking()
        }

        override func mouseEntered(with event: NSEvent) {
            onHover?(index)
        }

        override func mouseDown(with event: NSEvent) {
            onClick?(index)
        }

        func matches(_ window: WindowInfo) -> Bool { false }

        override func draw(_ dirtyRect: NSRect) {
            guard isSelected else { return }
            NSColor.selectedContentBackgroundColor.withAlphaComponent(0.85).setFill()
            NSBezierPath(
                roundedRect: bounds.insetBy(dx: highlightInset, dy: highlightInset),
                xRadius: highlightRadius,
                yRadius: highlightRadius
            ).fill()
        }
    }

    // MARK: - List row

    private final class ListRow: Cell {
        private let pid: pid_t
        private let title: String

        init(window: WindowInfo, icon: NSImage?) {
            pid = window.pid
            title = window.title
            super.init(frame: .zero)

            wantsLayer = true
            translatesAutoresizingMaskIntoConstraints = false
            heightAnchor.constraint(equalToConstant: Metrics.current.rowHeight).isActive = true

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
                imageView.widthAnchor.constraint(equalToConstant: Metrics.current.iconSize),
                imageView.heightAnchor.constraint(equalToConstant: Metrics.current.iconSize),

                label.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 10),
                label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
                label.centerYAnchor.constraint(equalTo: centerYAnchor),
            ])
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("not used") }

        override func matches(_ window: WindowInfo) -> Bool {
            window.pid == pid && window.title == title
        }
    }

    // MARK: - Thumbnail cell

    private final class ThumbnailCell: Cell {
        let key: ThumbnailProvider.Key
        private let preview = NSImageView()
        private let badge: NSImageView

        override var highlightInset: CGFloat { 4 }
        override var highlightRadius: CGFloat { 10 }

        init(window: WindowInfo, icon: NSImage?, preview image: NSImage?) {
            key = ThumbnailProvider.Key(window)
            badge = NSImageView(image: icon ?? NSImage())
            super.init(frame: .zero)

            wantsLayer = true
            translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                widthAnchor.constraint(equalToConstant: Metrics.current.cellWidth),
                heightAnchor.constraint(equalToConstant: Metrics.current.cellHeight),
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

        override func matches(_ window: WindowInfo) -> Bool {
            ThumbnailProvider.Key(window) == key
        }
    }

    // MARK: - App icon cell

    /// A large app icon with the window title beneath it.
    ///
    /// This layout needs no capture and no screen recording permission, which makes it the
    /// only visual layout available before that permission is granted. Its weakness is the
    /// case this project exists for: several windows of one app render as identical icons,
    /// distinguishable only by the title underneath.
    private final class IconCell: Cell {
        private let pid: pid_t
        private let title: String

        override var highlightInset: CGFloat { 4 }
        override var highlightRadius: CGFloat { 10 }

        init(window: WindowInfo, icon: NSImage?) {
            pid = window.pid
            title = window.title
            super.init(frame: .zero)

            wantsLayer = true
            translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                widthAnchor.constraint(equalToConstant: Metrics.current.iconCellWidth),
                heightAnchor.constraint(equalToConstant: Metrics.current.iconCellHeight),
            ])

            let imageView = NSImageView(image: icon ?? NSImage())
            imageView.imageScaling = .scaleProportionallyUpOrDown
            imageView.translatesAutoresizingMaskIntoConstraints = false

            let label = NSTextField(labelWithString: window.displayTitle)
            label.lineBreakMode = .byTruncatingTail
            label.alignment = .center
            label.font = .systemFont(ofSize: 10)
            label.textColor = .secondaryLabelColor
            label.translatesAutoresizingMaskIntoConstraints = false

            addSubview(imageView)
            addSubview(label)

            NSLayoutConstraint.activate([
                imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
                imageView.topAnchor.constraint(equalTo: topAnchor, constant: 12),
                imageView.widthAnchor.constraint(equalToConstant: Metrics.current.largeIconSize),
                imageView.heightAnchor.constraint(equalToConstant: Metrics.current.largeIconSize),

                label.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 6),
                label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
                label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            ])
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("not used") }

        override func matches(_ window: WindowInfo) -> Bool {
            window.pid == pid && window.title == title
        }
    }
}

extension WindowInfo {
    var displayTitle: String {
        title.isEmpty ? "(untitled)" : title
    }
}
