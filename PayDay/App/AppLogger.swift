import Foundation
import os

enum LogCategory: String, Sendable, CaseIterable {
    case app, auth, db, invoice, pdf, einvoice, peppol, vat, credits, ui
}

enum LogLevel: String, Sendable {
    case debug, info, warn, error
}

final class AppLogger: Sendable {
    static let shared = AppLogger()

    private let loggers: [LogCategory: Logger]
    private let fileQueue = DispatchQueue(label: "com.guitaripod.payday.logger.file", qos: .utility)
    private let fileURL: URL?
    private let previousURL: URL?
    private let maxBytes = 2 * 1024 * 1024

    private init() {
        let subsystem = Bundle.main.bundleIdentifier ?? "com.guitaripod.payday"
        var built: [LogCategory: Logger] = [:]
        for category in LogCategory.allCases {
            built[category] = Logger(subsystem: subsystem, category: category.rawValue)
        }
        self.loggers = built

        let logs = try? FileManager.default.url(
            for: .libraryDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        ).appendingPathComponent("Logs", isDirectory: true)
        if let logs {
            try? FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
            self.fileURL = logs.appendingPathComponent("payday.log")
            self.previousURL = logs.appendingPathComponent("payday.previous.log")
        } else {
            self.fileURL = nil
            self.previousURL = nil
        }
    }

    func log(_ level: LogLevel, _ message: @autoclosure () -> String, category: LogCategory) {
        let text = message()
        let logger = loggers[category] ?? Logger()
        switch level {
        case .debug: logger.debug("\(text, privacy: .public)")
        case .info: logger.info("\(text, privacy: .public)")
        case .warn: logger.warning("\(text, privacy: .public)")
        case .error: logger.error("\(text, privacy: .public)")
        }
        writeToFile(level: level, category: category, text: text)
    }

    func debug(_ message: @autoclosure () -> String, category: LogCategory) { log(.debug, message(), category: category) }
    func info(_ message: @autoclosure () -> String, category: LogCategory) { log(.info, message(), category: category) }
    func warn(_ message: @autoclosure () -> String, category: LogCategory) { log(.warn, message(), category: category) }
    func error(_ message: @autoclosure () -> String, category: LogCategory) { log(.error, message(), category: category) }

    private func writeToFile(level: LogLevel, category: LogCategory, text: String) {
        guard let fileURL, let previousURL else { return }
        let line = "\(Self.timestamp()) [\(ProcessInfo.processInfo.processIdentifier)] [\(level.rawValue)] [\(category.rawValue)] \(text)\n"
        fileQueue.async {
            Self.rotateIfNeeded(at: fileURL, previous: previousURL, maxBytes: self.maxBytes)
            guard let data = line.data(using: .utf8) else { return }
            if let handle = try? FileHandle(forWritingTo: fileURL) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            } else {
                try? data.write(to: fileURL)
            }
        }
    }

    private static func rotateIfNeeded(at fileURL: URL, previous: URL, maxBytes: Int) {
        let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
        let size = (attributes?[.size] as? Int) ?? 0
        guard size > maxBytes else { return }
        try? FileManager.default.removeItem(at: previous)
        try? FileManager.default.moveItem(at: fileURL, to: previous)
    }

    private static func timestamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }
}
