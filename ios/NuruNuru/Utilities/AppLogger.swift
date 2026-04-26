import Foundation
import os

/// Unified logging for NuruNuru — uses os.Logger so logs are readable via
/// `log stream --predicate 'subsystem == "io.nurunuru.app"'` on a connected Mac.
///
/// Also writes to a local log file for retrieval when Xcode console is unavailable.
enum AppLogger {

    // MARK: - os.Logger instances (per-category)

    static let relay      = Logger(subsystem: subsystem, category: "Relay")
    static let repository = Logger(subsystem: subsystem, category: "Repository")
    static let bookmarks  = Logger(subsystem: subsystem, category: "Bookmarks")
    static let badges     = Logger(subsystem: subsystem, category: "Badges")
    static let nip65      = Logger(subsystem: subsystem, category: "NIP65")
    static let timeline   = Logger(subsystem: subsystem, category: "Timeline")
    static let general    = Logger(subsystem: subsystem, category: "General")

    private static let subsystem = "io.nurunuru.app"

    // MARK: - File logging

    /// Log file path — in the app's Documents directory for easy retrieval.
    static var logFilePath: String {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("nurunuru_debug.log").path
    }

    /// Append a line to the log file + print to stdout + os_log.
    static func log(_ category: String, _ message: String, level: OSLogType = .default) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(timestamp)] [\(category)] \(message)"

        // os_log (readable via `log stream`)
        let logger = Logger(subsystem: subsystem, category: category)
        logger.log(level: level, "\(message, privacy: .public)")

        // print (Xcode console)
        print(line)

        // File (retrievable later)
        appendToFile(line)
    }

    /// Clear the log file.
    static func clearLogFile() {
        try? "".write(toFile: logFilePath, atomically: true, encoding: .utf8)
    }

    private static let fileQueue = DispatchQueue(label: "io.nurunuru.logger", qos: .utility)

    private static func appendToFile(_ line: String) {
        fileQueue.async {
            let path = logFilePath
            if !FileManager.default.fileExists(atPath: path) {
                FileManager.default.createFile(atPath: path, contents: nil)
            }
            guard let handle = FileHandle(forWritingAtPath: path) else { return }
            defer { handle.closeFile() }
            handle.seekToEndOfFile()
            if let data = (line + "\n").data(using: .utf8) {
                handle.write(data)
            }
        }
    }
}
