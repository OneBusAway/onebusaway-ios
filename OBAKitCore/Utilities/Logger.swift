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

// Immutable (a single os.Logger, which is Sendable); @unchecked only because NSObject is not Sendable.
@objc(OBALogger) public final class Logger: NSObject, @unchecked Sendable {

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
    public static func getLogEntries(since date: Date? = nil) throws -> [OSLogEntryLog] {
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
    public static func combinedLogContent() -> String {
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

    private static func levelString(for level: OSLogEntryLog.Level) -> String {
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

    // MARK: - Redaction

    /// Matches the query of an http(s) URL, up to whitespace, trailing
    /// punctuation, or a character `.urlQueryAllowed` always percent-encodes
    /// (`"`, `<`, `>`, `{`, `}`, `[`, `]`). `'`, `(` and `)` stay raw in a query,
    /// as in a search for "Lincoln's", so they don't end it.
    private static let urlQueryPattern = try! NSRegularExpression( // swiftlint:disable:this force_try
        pattern: #"(https?://[^\s?#"<>{}\[\]]+)\?[^\s"<>{}\[\]]*?(?=[,.;]?(?:[\s"<>{}\[\]]|$))"#
    )

    /// `message` with the query removed from every http(s) URL in it (#1732).
    ///
    /// Every message is logged `.public`, and callers often interpolate a raw
    /// error, whose description includes the failing URL. The query holds the
    /// region's API key, the install's `app_uid` and, for calls like
    /// stops-for-location, the rider's coordinates.
    static func redactingURLQueries(in message: String) -> String {
        guard message.contains("?") else { return message }
        let range = NSRange(message.startIndex..., in: message)
        return urlQueryPattern.stringByReplacingMatches(in: message, range: range, withTemplate: "$1")
    }

    // MARK: - Info

    @objc public static func info(_ message: String) {
        shared.info(message)
    }

    func info(_ message: String) {
        logger.info("\(Self.redactingURLQueries(in: message), privacy: .public)")
    }

    // MARK: - Warn

    @objc public static func warn(_ message: String) {
        shared.warn(message)
    }

    func warn(_ message: String) {
        logger.warning("\(Self.redactingURLQueries(in: message), privacy: .public)")
    }

    // MARK: - Error

    @objc public static func error(_ message: String) {
        shared.error(message)
    }

    func error(_ message: String) {
        logger.error("\(Self.redactingURLQueries(in: message), privacy: .public)")
    }
}
