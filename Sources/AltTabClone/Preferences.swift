import Foundation

/// How the switcher presents windows.
enum PanelLayout: String, CaseIterable {
    /// One window per row: app icon and full title. Reads long titles well, and is the
    /// only useful layout when several windows of one app differ solely by title.
    case list

    /// A grid of window previews. Faster to recognise a window by content, at the cost of
    /// truncated titles and a capture that has to be fetched.
    case thumbnails

    /// A compact row of large app icons. The fastest layout to scan when the windows you
    /// switch between belong to different apps, and the least useful when several belong
    /// to the same one — every entry looks identical.
    case appIcons

    var label: String {
        switch self {
        case .list: "List"
        case .thumbnails: "Thumbnails"
        case .appIcons: "App Icons"
        }
    }

    /// Whether this layout needs window captures, and therefore screen recording.
    var needsCapture: Bool { self == .thumbnails }
}

/// Panel scale. Applied as a multiplier over the base metrics rather than as three sets of
/// hardcoded numbers, so the layouts stay proportional.
enum PanelSize: String, CaseIterable {
    case small, medium, large

    var scale: CGFloat {
        switch self {
        case .small: 0.8
        case .medium: 1.0
        case .large: 1.25
        }
    }

    var label: String { rawValue.capitalized }
}

/// Which display the panel opens on when more than one is attached.
enum ScreenChoice: String, CaseIterable {
    /// The screen holding the pointer — usually the one being looked at.
    case pointer

    /// The screen with the menu bar, regardless of where the pointer is.
    case main

    var label: String {
        switch self {
        case .pointer: "Active screen"
        case .main: "Main screen"
        }
    }
}

/// Persisted settings.
///
/// Backed by UserDefaults rather than a config file: these are a handful of values changed
/// from a settings window, and a switcher that forgot them on every launch would be
/// irritating out of proportion to the settings themselves.
///
/// Every setting here changes real behaviour. Nothing is exposed that the switcher cannot
/// actually do — a control that moves nothing is worse than a missing one, because it
/// claims a capability that does not exist.
enum Preferences {
    /// Posted when any setting changes, so views built from these values can be discarded
    /// and rebuilt rather than showing stale geometry until the window list happens to
    /// change.
    static let didChange = Notification.Name("PreferencesDidChange")

    static var layout: PanelLayout {
        get { read("panelLayout") ?? .list }
        set { write(newValue, "panelLayout") }
    }

    static var size: PanelSize {
        get { read("panelSize") ?? .medium }
        set { write(newValue, "panelSize") }
    }

    static var screen: ScreenChoice {
        get { read("screenChoice") ?? .pointer }
        set { write(newValue, "screenChoice") }
    }

    /// Cycles every window. Defaults to Option+Tab.
    static var allWindowsShortcut: Shortcut {
        get { shortcut("shortcutAllWindows") ?? Shortcut(keyCode: 48, modifiers: .maskAlternate) }
        set { store(newValue, "shortcutAllWindows") }
    }

    /// Cycles windows of the focused app only. Defaults to Option+`, mirroring the
    /// system's own Command+`.
    static var sameAppShortcut: Shortcut {
        get { shortcut("shortcutSameApp") ?? Shortcut(keyCode: 50, modifiers: .maskAlternate) }
        set { store(newValue, "shortcutSameApp") }
    }

    /// Moves to the next Space. Defaults to Control+Tab.
    ///
    /// Worth knowing before keeping the default: Control+Tab is how browsers and editors
    /// switch their own tabs, and a global trigger takes it away from all of them. It is
    /// rebindable for exactly that reason.
    static var spaceShortcut: Shortcut {
        get { shortcut("shortcutSpace") ?? Shortcut(keyCode: 48, modifiers: .maskControl) }
        set { store(newValue, "shortcutSpace") }
    }

    private static func shortcut(_ key: String) -> Shortcut? {
        UserDefaults.standard.string(forKey: key).flatMap(Shortcut.init(storage:))
    }

    private static func store(_ value: Shortcut, _ key: String) {
        UserDefaults.standard.set(value.storage, forKey: key)
        NotificationCenter.default.post(name: didChange, object: nil)
    }

    /// Upper bound on rows or cells drawn. A switcher listing sixty windows is not a
    /// switcher; past a point, scanning the list costs more than finding the window
    /// another way.
    static var maxWindows: Int {
        get {
            let stored = UserDefaults.standard.integer(forKey: "maxWindows")
            return stored == 0 ? 15 : stored
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "maxWindows")
            NotificationCenter.default.post(name: didChange, object: nil)
        }
    }

    // MARK: - Storage

    private static func read<T: RawRepresentable>(_ key: String) -> T? where T.RawValue == String {
        UserDefaults.standard.string(forKey: key).flatMap(T.init(rawValue:))
    }

    private static func write<T: RawRepresentable>(_ value: T, _ key: String) where T.RawValue == String {
        UserDefaults.standard.set(value.rawValue, forKey: key)
        NotificationCenter.default.post(name: didChange, object: nil)
    }
}
