import AppKit

/// A field that records a key combination by having the user perform it.
///
/// Recording beats a pair of pickers because a shortcut is a physical gesture: what
/// matters is whether the combination is comfortable and whether the keyboard actually
/// produces it, and neither is answerable from a dropdown.
final class ShortcutRecorder: NSView {
    var onChange: ((Shortcut) -> Void)?

    private var shortcut: Shortcut
    private var monitor: Any?
    private let label = NSTextField(labelWithString: "")

    private var isRecording = false {
        didSet {
            refresh()
            needsDisplay = true
        }
    }

    init(shortcut: Shortcut) {
        self.shortcut = shortcut
        super.init(frame: .zero)

        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 130),
            heightAnchor.constraint(equalToConstant: 24),
        ])

        label.alignment = .center
        label.font = .systemFont(ofSize: 12)
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        refresh()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    deinit {
        stop()
    }

    // MARK: - Recording

    override func mouseDown(with event: NSEvent) {
        isRecording ? stop() : start()
    }

    private func start() {
        isRecording = true

        // A local monitor rather than first-responder key handling: the returned nil
        // swallows the event, so recording ⌘Q does not also quit the app.
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            self?.record(event)
            return nil
        }
    }

    private func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        isRecording = false
    }

    private func record(_ event: NSEvent) {
        // Escape abandons recording rather than being captured. Binding the switcher to
        // Escape would collide with the cancel key the switcher itself uses.
        if event.keyCode == 53 {
            stop()
            return
        }

        let candidate = Shortcut(
            keyCode: Int64(event.keyCode),
            modifiers: CGEventFlags(rawValue: UInt64(event.modifierFlags.rawValue))
        )

        guard candidate.isValid else {
            // Rejected rather than stored: the gesture commits when the modifier is
            // released, so a trigger without one would record cleanly and then never fire.
            label.stringValue = "Needs ⌘, ⌥ or ⌃"
            return
        }

        shortcut = candidate
        stop()
        onChange?(candidate)
    }

    // MARK: - Drawing

    private func refresh() {
        label.stringValue = isRecording ? "Press keys…" : shortcut.display
        label.textColor = isRecording ? .secondaryLabelColor : .labelColor
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 5, yRadius: 5)
        (isRecording ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
        NSColor.controlBackgroundColor.setFill()
        path.fill()
        path.lineWidth = isRecording ? 2 : 1
        path.stroke()
    }
}
