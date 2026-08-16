import AppKit

/// The settings window.
///
/// Deliberately small. Every control here changes behaviour the switcher actually has;
/// nothing is shown for a capability that does not exist yet, because a switch that moves
/// nothing is a promise the app cannot keep.
final class SettingsWindow: NSObject, NSWindowDelegate {
    private var window: NSWindow?

    func show() {
        let window = window ?? make()
        self.window = window

        // The settings window is the one place this app legitimately takes focus: the user
        // asked for it, and unlike the switcher panel it is not trying to stay out of the
        // way while measuring what was focused before.
        NSApplication.shared.activate()
        window.makeKeyAndOrderFront(nil)
        window.center()
    }

    // MARK: - Construction

    private func make() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 300),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "AltTabClone Settings"
        window.delegate = self
        window.isReleasedWhenClosed = false

        let form = NSStackView(views: [
            section("Shortcuts"),
            row("All windows", recorder(Preferences.allWindowsShortcut) { Preferences.allWindowsShortcut = $0 }),
            row("Current app", recorder(Preferences.sameAppShortcut) { Preferences.sameAppShortcut = $0 }),
            hint("Hold the modifier, tap the key, release to switch."),

            section("Appearance"),
            row("Layout", segmented(PanelLayout.allCases.map(\.label), selected: index(of: Preferences.layout)) { index in
                Preferences.layout = PanelLayout.allCases[index]
            }),
            row("Size", segmented(PanelSize.allCases.map(\.label), selected: index(of: Preferences.size)) { index in
                Preferences.size = PanelSize.allCases[index]
            }),

            section("Behaviour"),
            row("Show on", segmented(ScreenChoice.allCases.map(\.label), selected: index(of: Preferences.screen)) { index in
                Preferences.screen = ScreenChoice.allCases[index]
            }),
            row("Max windows", stepper()),
        ])
        form.orientation = .vertical
        form.alignment = .leading
        form.spacing = 12
        form.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        form.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView()
        content.addSubview(form)
        // Pinned on all four edges, so the form drives the window's size instead of being
        // clipped by whatever height the window was created with.
        NSLayoutConstraint.activate([
            form.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            form.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            form.topAnchor.constraint(equalTo: content.topAnchor),
            form.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])
        window.contentView = content

        // Width is fixed and only the height is measured. Letting the form decide both
        // makes the window as wide as its longest line of explanatory text, which is a
        // terrible way to choose a window width.
        //
        // Sized to fit rather than scrolled: this form is short enough to show whole on
        // any screen, and a scroll view would hide settings behind a gesture for no gain.
        let width: CGFloat = 460
        form.widthAnchor.constraint(equalToConstant: width).isActive = true
        window.setContentSize(NSSize(width: width, height: form.fittingSize.height))

        return window
    }

    // MARK: - Form pieces

    private func section(_ title: String) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.font = .boldSystemFont(ofSize: 13)
        return label
    }

    private func hint(_ text: String) -> NSView {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        return label
    }

    private func recorder(_ shortcut: Shortcut, onChange: @escaping (Shortcut) -> Void) -> NSView {
        let recorder = ShortcutRecorder(shortcut: shortcut)
        recorder.onChange = onChange
        return recorder
    }

    private func row(_ title: String, _ control: NSView) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.alignment = .right
        label.translatesAutoresizingMaskIntoConstraints = false
        label.widthAnchor.constraint(equalToConstant: 110).isActive = true

        let stack = NSStackView(views: [label, control])
        stack.orientation = .horizontal
        stack.spacing = 12
        stack.alignment = .centerY
        return stack
    }

    private func index<T: CaseIterable & Equatable>(of value: T) -> Int {
        Array(T.allCases).firstIndex(of: value) ?? 0
    }

    private func segmented(_ labels: [String], selected: Int, onChange: @escaping (Int) -> Void) -> NSSegmentedControl {
        let control = SegmentedControl(labels: labels, onChange: onChange)
        control.selectedSegment = selected
        return control
    }

    private func stepper() -> NSView {
        let field = NSTextField(labelWithString: "\(Preferences.maxWindows)")
        field.translatesAutoresizingMaskIntoConstraints = false
        field.widthAnchor.constraint(equalToConstant: 30).isActive = true

        let stepper = Stepper { value in
            Preferences.maxWindows = value
            field.stringValue = "\(value)"
        }
        stepper.minValue = 3
        stepper.maxValue = 30
        stepper.integerValue = Preferences.maxWindows

        let stack = NSStackView(views: [field, stepper])
        stack.orientation = .horizontal
        stack.spacing = 6
        return stack
    }

    // MARK: - Controls
    //
    // AppKit's target/action predates closures, so each control needs an object that
    // outlives it to receive the action. These subclasses hold their own handler rather
    // than routing every control through one switch statement in the window.

    private final class SegmentedControl: NSSegmentedControl {
        private let onChange: (Int) -> Void

        init(labels: [String], onChange: @escaping (Int) -> Void) {
            self.onChange = onChange
            super.init(frame: .zero)
            segmentCount = labels.count
            segmentStyle = .rounded
            trackingMode = .selectOne
            for (index, label) in labels.enumerated() {
                setLabel(label, forSegment: index)
                setWidth(0, forSegment: index)
            }
            target = self
            action = #selector(changed)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("not used") }

        @objc private func changed() {
            onChange(selectedSegment)
        }
    }

    private final class Stepper: NSStepper {
        private let onChange: (Int) -> Void

        init(onChange: @escaping (Int) -> Void) {
            self.onChange = onChange
            super.init(frame: .zero)
            valueWraps = false
            target = self
            action = #selector(changed)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("not used") }

        @objc private func changed() {
            onChange(integerValue)
        }
    }
}
