import ApplicationServices
import CoreGraphics

/// Thin, type-safe wrappers over the Accessibility C API.
///
/// Every `AXUIElementCopyAttributeValue` call returns an untyped `CFTypeRef?` plus an
/// error code. These helpers collapse that into an optional so callers can use `guard let`
/// instead of repeating the same six lines at each call site.
enum AX {
    /// Reads an attribute and bridges it to `T`, or returns nil if the attribute is
    /// missing, unsupported by the element, or of an unexpected type.
    static func attribute<T>(_ element: AXUIElement, _ name: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else {
            return nil
        }
        return value as? T
    }

    /// Reads an attribute boxed in an `AXValue`.
    ///
    /// Position and size are not plain CF types: they arrive boxed in an `AXValue` that
    /// must be unpacked with `AXValueGetValue` into a caller-provided struct.
    ///
    /// `Unpacked` is constrained to `BitwiseCopyable` on purpose. `AXValueGetValue` writes
    /// raw bytes through the pointer, so a type holding an object reference would have that
    /// reference overwritten rather than assigned.
    private static func boxedValue<Unpacked: BitwiseCopyable>(
        _ element: AXUIElement,
        _ name: String,
        as type: AXValueType
    ) -> Unpacked? {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &raw) == .success,
              let raw, CFGetTypeID(raw) == AXValueGetTypeID() else {
            return nil
        }
        let storage = UnsafeMutablePointer<Unpacked>.allocate(capacity: 1)
        defer { storage.deallocate() }
        // Only read the buffer back on success; on failure it stays uninitialized.
        guard AXValueGetValue(raw as! AXValue, type, storage) else { return nil }
        return storage.pointee
    }

    /// The window's frame in screen coordinates, or nil if either half is unreadable.
    static func frame(of window: AXUIElement) -> CGRect? {
        guard let origin: CGPoint = boxedValue(window, kAXPositionAttribute as String, as: .cgPoint),
              let size: CGSize = boxedValue(window, kAXSizeAttribute as String, as: .cgSize) else {
            return nil
        }
        return CGRect(origin: origin, size: size)
    }

    /// Whether this process currently holds the Accessibility permission.
    ///
    /// Pass `prompt: true` to make macOS show the "open System Settings" dialog. The
    /// dialog is shown at most once per app identity, which is exactly why the binary
    /// needs a stable code signature across rebuilds.
    static func isTrusted(prompt: Bool) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    /// Prompts for Accessibility permission and waits for the user to grant it.
    ///
    /// The prompt is fire-and-forget: `AXIsProcessTrustedWithOptions` returns false
    /// immediately while the dialog is still on screen. Without this wait the process
    /// would exit before the user finished, forcing a rerun after every grant. Polling
    /// is the only option here — the API publishes no notification for the transition.
    static func waitForTrust(timeout: TimeInterval) -> Bool {
        if isTrusted(prompt: true) { return true }

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            Thread.sleep(forTimeInterval: 0.5)
            if isTrusted(prompt: false) { return true }
        }
        return false
    }
}
