import Foundation

/// How the switcher presents windows.
enum PanelLayout: String {
    /// One window per row: app icon and full title. Reads long titles well, and is the
    /// only useful layout when several windows of one app differ solely by title.
    case list

    /// A grid of window previews. Faster to recognise a window by what is in it, at the
    /// cost of truncated titles and a capture that has to be fetched.
    case thumbnails
}

/// Persisted settings.
///
/// Backed by UserDefaults rather than a config file: this is one value that changes from a
/// menu, and a switcher that forgot its layout on every launch would be irritating in a way
/// out of proportion to the setting.
enum Preferences {
    private static let layoutKey = "panelLayout"

    static var layout: PanelLayout {
        get {
            UserDefaults.standard.string(forKey: layoutKey)
                .flatMap(PanelLayout.init(rawValue:)) ?? .list
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: layoutKey)
        }
    }
}
