import AppKit
import CoreGraphics

/// A hold-and-tap trigger: one or more modifiers held down, plus a key tapped while they
/// are held.
///
/// The modifiers are not decoration. The whole interaction is hold-modifier, tap-key,
/// release-to-commit, so releasing them is the only signal that the user has chosen. A
/// trigger with no modifier has nothing to release and cannot work at all — which is why
/// `isValid` rejects it rather than storing something that silently never fires.
struct Shortcut: Equatable {
    var keyCode: Int64
    var modifiers: CGEventFlags

    /// Shift is excluded from the requirement on purpose: the gesture already uses it to
    /// reverse direction, so a Shift-only trigger would be ambiguous with going backwards.
    static let requiredOneOf: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl]

    /// Modifier bits worth storing. Everything else — caps lock, numeric pad, function
    /// key flags — is noise that would make an otherwise identical press fail to match.
    static let relevant: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl, .maskShift]

    var isValid: Bool {
        !modifiers.intersection(Self.requiredOneOf).isEmpty
    }

    /// Whether an event's flags satisfy this trigger.
    ///
    /// Shift is ignored when matching because it selects direction rather than forming
    /// part of the trigger; `⌥⇥` and `⌥⇧⇥` are the same shortcut going opposite ways.
    func matches(flags: CGEventFlags) -> Bool {
        let wanted = modifiers.intersection(Self.relevant).subtracting(.maskShift)
        return flags.intersection(wanted) == wanted
    }

    /// The modifiers whose release commits the selection.
    var holdModifiers: CGEventFlags {
        modifiers.intersection(Self.requiredOneOf)
    }

    // MARK: - Display

    var display: String {
        let symbols = [
            (CGEventFlags.maskControl, "⌃"),
            (.maskAlternate, "⌥"),
            (.maskShift, "⇧"),
            (.maskCommand, "⌘"),
        ]
        let prefix = symbols.filter { modifiers.contains($0.0) }.map(\.1).joined()
        return prefix + Self.name(for: keyCode)
    }

    /// Names for the keys people actually bind a switcher to. Anything else falls back to
    /// its raw code, which is unlovely but honest — inventing a label for an unknown key
    /// would be worse than showing what was recorded.
    static func name(for keyCode: Int64) -> String {
        switch keyCode {
        case 48: "⇥"
        case 50: "`"
        case 49: "Space"
        case 53: "⎋"
        case 36: "↩"
        case 51: "⌫"
        case 123: "←"
        case 124: "→"
        case 125: "↓"
        case 126: "↑"
        case 0: "A"; case 1: "S"; case 2: "D"; case 3: "F"; case 4: "H"
        case 5: "G"; case 6: "Z"; case 7: "X"; case 8: "C"; case 9: "V"
        case 11: "B"; case 12: "Q"; case 13: "W"; case 14: "E"; case 15: "R"
        case 16: "Y"; case 17: "T"; case 31: "O"; case 32: "U"; case 34: "I"
        case 35: "P"; case 37: "L"; case 38: "J"; case 40: "K"; case 45: "N"
        case 46: "M"
        default: "key \(keyCode)"
        }
    }

    // MARK: - Storage

    /// Stored as a single string so the whole trigger is written and read atomically. Two
    /// separate defaults keys could be half-updated and produce a shortcut nobody chose.
    var storage: String { "\(modifiers.rawValue):\(keyCode)" }

    init(keyCode: Int64, modifiers: CGEventFlags) {
        self.keyCode = keyCode
        self.modifiers = modifiers.intersection(Self.relevant)
    }

    init?(storage: String) {
        let parts = storage.split(separator: ":")
        guard parts.count == 2,
              let raw = UInt64(parts[0]),
              let code = Int64(parts[1]) else {
            return nil
        }
        self.init(keyCode: code, modifiers: CGEventFlags(rawValue: raw))
    }
}
