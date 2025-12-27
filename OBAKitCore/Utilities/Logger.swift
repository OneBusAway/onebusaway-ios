//
//  Logger.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import OSLog

@objc(OBALogger) public class Logger: NSObject {

    static let shared = Logger()

    private let logger: os.Logger
    private static let subsystem = Bundle.main.bundleIdentifier
    private static let category = "app"

    override init() {
        logger = os.Logger(subsystem: Self.subsystem, category: Self.category)
        super.init()
    }

    // MARK: - Log Access

    /// Returns log entries from OSLogStore for the app's subsystem
    /// - Parameter since: Optional date to filter logs from. If nil, returns logs since boot.
    /// - Returns: Array of log entries
    public class func getLogEntries(since date: Date? = nil) throws -> [OSLogEntryLog] {
        let store = try OSLogStore(scope: .currentProcessIdentifier)
        let position: OSLogPosition
        if let date = date {
            position = store.position(date: date)
        } else {
            position = store.position(timeIntervalSinceLatestBoot: 0)
        }

        let predicate = NSPredicate(format: "subsystem == %@", subsystem)
        let entries = try store.getEntries(at: position, matching: predicate)

        return entries.compactMap { $0 as? OSLogEntryLog }
    }

    /// Reads and returns the combined content of all log entries
    public class func combinedLogContent() -> String {
        do {
            let entries = try getLogEntries()
            if entries.isEmpty {
                return ""
            }
            return entries.map { entry in
                let level = levelString(for: entry.level)
                let date = entry.date.formatted(.iso8601)
                return "[\(date)] [\(level)] \(entry.composedMessage)"
            }.joined(separator: "\n")
        } catch {
            return "Error reading logs: \(error.localizedDescription)"
        }
    }

    private class func levelString(for level: OSLogEntryLog.Level) -> String {
        switch level {
        case .undefined: return "UNDEFINED"
        case .debug: return "DEBUG"
        case .info: return "INFO"
        case .notice: return "NOTICE"
        case .error: return "ERROR"
        case .fault: return "FAULT"
        @unknown default: return "UNKNOWN"
        }
    }

    // MARK: - Info

    @objc public class func info(_ message: String) {
        shared.info(message)
    }

    func info(_ message: String) {
        logger.info("\(message, privacy: .public)")
    }

    // MARK: - Warn

    @objc public class func warn(_ message: String) {
        shared.warn(message)
    }

    func warn(_ message: String) {
        logger.warning("\(message, privacy: .public)")
    }

    // MARK: - Error

    @objc public class func error(_ message: String) {
        shared.error(message)
    }

    func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
    }
}
