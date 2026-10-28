import Foundation
import os

/// Timestamped lines on screen and in Documents/backtalk.log.
final class Log {
    static let shared = Log()
    static let changed = Notification.Name("LogChanged")
    private(set) var lines: [String] = []
    private let logger = Logger(subsystem: "com.bgrayson.backtalk", category: "app")
    private let file: FileHandle?
    private let stamp: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    private init() {
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("backtalk.log")
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        file = try? FileHandle(forWritingTo: url)
        file?.seekToEndOfFile()
    }

    func add(_ message: String) {
        let line = "\(stamp.string(from: Date())) \(message)"
        logger.log("\(line, privacy: .public)")
        DispatchQueue.main.async {
            self.lines.append(line)
            if self.lines.count > 300 { self.lines.removeFirst(100) }
            self.file?.write(Data((line + "\n").utf8))
            NotificationCenter.default.post(name: Log.changed, object: nil)
        }
    }
}

func log(_ message: String) { Log.shared.add(message) }
