import ApplicationServices

/// Most-recently-used ordering for windows.
///
/// macOS publishes no MRU window list, so it has to be accumulated by watching focus
/// change over time. This is what turns the switcher from a process that answers a
/// question into one that has to keep running to be useful.
///
/// Window identity comes from `CFEqual` on the `AXUIElement`: two references to the same
/// window compare equal. Titles change as documents are edited and frames change when
/// windows are moved, so neither can identify a window across two enumerations.
final class WindowHistory {
    /// Most recent first. Small by nature — a few dozen entries at most — so linear
    /// scanning costs less than maintaining a hash of a CFType.
    private var order: [AXUIElement] = []

    /// Records that a window just received focus, moving it to the front.
    func recordFocus(_ element: AXUIElement) {
        order.removeAll { CFEqual($0, element) }
        order.insert(element, at: 0)
    }

    /// Drops windows that no longer exist, so closed windows do not accumulate forever.
    func prune(keeping live: [WindowInfo]) {
        order.removeAll { entry in
            !live.contains { CFEqual($0.element, entry) }
        }
    }

    /// Orders `windows` most-recently-used first.
    ///
    /// Windows never seen focused are unranked and keep their enumeration order at the
    /// back. That matters at startup, when history is empty and everything is unranked.
    func sorted(_ windows: [WindowInfo]) -> [WindowInfo] {
        let ranked = windows.compactMap { window -> (Int, WindowInfo)? in
            guard let rank = order.firstIndex(where: { CFEqual($0, window.element) }) else {
                return nil
            }
            return (rank, window)
        }
        let unranked = windows.filter { window in
            !order.contains { CFEqual($0, window.element) }
        }
        return ranked.sorted { $0.0 < $1.0 }.map(\.1) + unranked
    }
}
