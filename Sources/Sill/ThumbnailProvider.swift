import AppKit
import ScreenCaptureKit

/// Fetches window previews through ScreenCaptureKit.
///
/// Capture is asynchronous and not cheap. Blocking the switcher until every window has been
/// captured would make a keystroke feel broken, so the panel is shown immediately with
/// icons and each preview is delivered as it arrives.
///
/// This is also why results are cached: cycling back and forth through the same windows is
/// the common case, and recapturing on every Tab would spend real time redrawing pictures
/// the user just saw.
final class ThumbnailProvider {
    /// Windows are keyed by owning process and title. ScreenCaptureKit identifies windows
    /// by `CGWindowID`, which the Accessibility API never exposes publicly, so the two
    /// views of the same window have to be matched on what they both report.
    struct Key: Hashable {
        let pid: pid_t
        let title: String

        init(_ window: WindowInfo) {
            pid = window.pid
            title = window.title
        }
    }

    private var cache: [Key: NSImage] = [:]
    private let report: Report

    init(report: Report) {
        self.report = report
    }

    /// Whether screen recording has been granted. Unlike Accessibility, this cannot be
    /// polled into existence — the prompt appears once and the user must act on it.
    static func hasPermission() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    @discardableResult
    static func requestPermission() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    func cached(for window: WindowInfo) -> NSImage? {
        cache[Key(window)]
    }

    /// Captures previews for `windows`, calling `onImage` on the main queue as each
    /// arrives. Already-cached windows are reported immediately and never recaptured.
    func fetch(for windows: [WindowInfo], onImage: @escaping (Key, NSImage) -> Void) {
        let missing = windows.filter { cache[Key($0)] == nil }
        guard !missing.isEmpty else { return }

        Task { [weak self] in
            guard let self else { return }
            do {
                // Desktop windows are excluded here for the same reason the enumerator
                // filters them: they are not things a user switches to.
                let content = try await SCShareableContent.excludingDesktopWindows(
                    true,
                    onScreenWindowsOnly: true
                )

                var captured = 0
                var unmatched = 0

                for window in missing {
                    guard let match = content.windows.first(where: {
                        $0.owningApplication?.processID == window.pid && $0.title == window.title
                    }) else {
                        // Matching is on pid and title because ScreenCaptureKit identifies
                        // windows by CGWindowID, which Accessibility never exposes
                        // publicly. Titles that differ between the two views land here.
                        unmatched += 1
                        continue
                    }

                    guard let image = await self.capture(match) else { continue }
                    captured += 1
                    let key = Key(window)
                    await MainActor.run {
                        self.cache[key] = image
                        onImage(key, image)
                    }
                }

                // Snapshotted into constants before crossing to the main actor: passing the
                // mutable counters into a concurrently-executing closure is an error under
                // the Swift 6 language mode.
                let summary = "thumbnails: \(captured) captured, \(unmatched) unmatched, "
                    + "\(content.windows.count) offered by ScreenCaptureKit"
                await MainActor.run {
                    self.report.add(summary)
                }
            } catch {
                // The usual cause is screen recording not being granted. Surfacing it
                // beats a panel that silently shows no previews forever.
                await MainActor.run {
                    self.report.add("thumbnail capture failed: \(error.localizedDescription)")
                }
            }
        }
    }

    private func capture(_ window: SCWindow) async -> NSImage? {
        let configuration = SCStreamConfiguration()
        // Captured at roughly the cell size rather than full resolution: these are
        // thumbnails, and full-size captures of a 4K window cost time and memory for
        // pixels that are thrown away on scaling.
        let scale = min(320 / max(window.frame.width, 1), 200 / max(window.frame.height, 1))
        configuration.width = Int(window.frame.width * scale)
        configuration.height = Int(window.frame.height * scale)
        configuration.showsCursor = false

        let filter = SCContentFilter(desktopIndependentWindow: window)
        guard let cgImage = try? await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: configuration
        ) else {
            return nil
        }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }
}
