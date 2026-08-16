import Foundation

/// Streams probe output to stdout and to a log file, one line at a time.
///
/// The log file exists because of how the app has to be launched: `open` gives the
/// process its own identity for permission purposes, but detaches stdout.
///
/// Lines are flushed as they are produced rather than buffered until the end. Accessibility
/// calls block on other processes, so a run that hangs is a normal failure mode here — and a
/// log that is only written on completion says nothing about where it stopped.
struct Report {
    static let logURL = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent("Library/Logs/AltTabClone.log")

    private let handle: FileHandle?

    init() {
        let manager = FileManager.default
        try? manager.createDirectory(
            at: Self.logURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        manager.createFile(atPath: Self.logURL.path, contents: nil)
        handle = try? FileHandle(forWritingTo: Self.logURL)
    }

    func add(_ line: String = "") {
        print(line)
        try? handle?.write(contentsOf: Data((line + "\n").utf8))
    }

    func close() {
        try? handle?.close()
    }
}
