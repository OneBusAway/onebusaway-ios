//
//  DecodingErrorReporter.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

public enum DecodingErrorReporter {

    private static let lock = NSLock()
    private static var _reportHandler: (@Sendable (_ error: DecodingError, _ url: URL, _ httpMethod: String, _ message: String) -> Void)?

    public static var reportHandler: (@Sendable (_ error: DecodingError, _ url: URL, _ httpMethod: String, _ message: String) -> Void)? {
        get { lock.withLock { _reportHandler } }
        set { lock.withLock { _reportHandler = newValue } }
    }

    public static func message(from error: DecodingError) -> String {
        switch error {
        case .keyNotFound(let key, let context):
            return """
            Missing key: '\(key.stringValue)'
            Path: \(path(context))
            Context: \(context.debugDescription)
            """

        case .typeMismatch(let type, let context):
            return """
            Type mismatch (expected \(type))
            Path: \(path(context))
            Context: \(context.debugDescription)
            """

        case .valueNotFound(let type, let context):
            return """
            Missing value (expected \(type))
            Path: \(path(context))
            Context: \(context.debugDescription)
            """

        case .dataCorrupted(let context):
            return """
            Data corrupted
            Path: \(path(context))
            Context: \(context.debugDescription)
            """

        @unknown default:
            return "Unknown decoding error encountered."
        }
    }

    public static func report(error: DecodingError, url: URL, httpMethod: String) {
        let errorMessage = message(from: error)

        guard let handler = reportHandler else {
            #if DEBUG
            print("[DecodingErrorReporter] Handler not configured. Error not reported: \(url.absoluteString)")
            #endif
            return
        }

        handler(error, url, httpMethod, errorMessage)
    }

    private static func path(_ context: DecodingError.Context) -> String {
        context.codingPath.isEmpty
            ? "root"
            : context.codingPath.map { $0.stringValue }.joined(separator: " → ")
    }
}
