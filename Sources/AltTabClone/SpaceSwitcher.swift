import CoreGraphics

/// Moves between Spaces by replaying the system's own Mission Control shortcut.
///
/// macOS exposes no public API for changing Space — AltTab and similar tools reach for
/// private CoreGraphics calls. What is public is synthesising keyboard input, so this
/// presses Control+Arrow on the user's behalf and lets macOS do the switching.
///
/// Two consequences follow from that, and neither is a bug to be fixed later:
///
/// - It depends on "Move left/right a space" still being enabled in Keyboard Shortcuts.
///   They are on by default; a user who turned them off gets nothing.
/// - There is no way to know which Space is current, or how many exist, so this cannot
///   show a panel the way window switching does. It is a discrete next/previous step
///   rather than a held gesture over a list.
enum SpaceSwitcher {
    private enum Key {
        static let leftArrow: CGKeyCode = 123
        static let rightArrow: CGKeyCode = 124
    }

    /// Stamped on every event this posts.
    ///
    /// The switcher's own event tap sees synthesised events just like real ones, so
    /// without a marker the Control+Arrow posted here could be read back as user input.
    static let syntheticMarker: Int64 = 0x414C5442  // "ALTB"

    static func move(next: Bool) {
        let source = CGEventSource(stateID: .hidSystemState)
        let key = next ? Key.rightArrow : Key.leftArrow

        for isDown in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: isDown) else {
                continue
            }
            event.flags = .maskControl
            event.setIntegerValueField(.eventSourceUserData, value: syntheticMarker)
            event.post(tap: .cgSessionEventTap)
        }
    }
}
