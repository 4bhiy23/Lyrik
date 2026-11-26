import Foundation

/// Tiny append-only diagnostic log at ~/Library/Logs/Lyrik.log.
enum Log {
    private static let queue = DispatchQueue(label: "lyrik.log")
    private static let url: URL = {
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("Lyrik.log")
    }()
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()
    private static var handle: FileHandle? = {
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        // Keep the log small: start over once it passes 2 MB.
        if let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int, size > 2_000_000 {
            try? Data().write(to: url)
        }
        let h = try? FileHandle(forWritingTo: url)
        h?.seekToEndOfFile()
        return h
    }()

    static func write(_ message: String) {
        let line = "\(formatter.string(from: Date()))  \(message)\n"
        queue.async {
            #if DEBUG
            FileHandle.standardError.write(line.data(using: .utf8)!)
            #endif
            handle?.write(line.data(using: .utf8)!)
        }
    }

    static var fileURL: URL { url }
}
