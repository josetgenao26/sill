import AppKit
import ApplicationServices

/// Brings a window to the front and moves keyboard focus to it.
enum WindowRaiser {
    /// Result of a raise attempt, broken down so a partial failure is visible.
    struct Outcome {
        let markedMain: Bool
        let raised: Bool
        let activated: Bool
    }

    /// Focusing a window takes three steps, and each one covers a different gap:
    ///
    /// - `kAXMainAttribute` tells the owning app which of its windows is the main one.
    ///   Without it the app restores focus to whichever window it already considered main,
    ///   which is what makes multi-window apps land on the wrong window.
    /// - `kAXRaiseAction` orders the window in front of its app's other windows. It has
    ///   no effect on which app owns keyboard focus.
    /// - `activate()` moves keyboard focus to the owning app. On its own it would focus
    ///   the app's existing main window, not the one requested here.
    ///
    /// All three return success from a process that has no run loop, while nothing actually
    /// happens: activation is an asynchronous request to the window server, and a process
    /// that exits before pumping its run loop never delivers it. The caller must keep a run
    /// loop alive across the call — the return values do not report this failure.
    @discardableResult
    static func raise(_ window: WindowInfo) -> Outcome {
        let markedMain = AXUIElementSetAttributeValue(
            window.element, kAXMainAttribute as CFString, kCFBooleanTrue
        ) == .success

        let raised = AXUIElementPerformAction(
            window.element, kAXRaiseAction as CFString
        ) == .success

        let activated = NSRunningApplication(processIdentifier: window.pid)?.activate() ?? false

        return Outcome(markedMain: markedMain, raised: raised, activated: activated)
    }
}
