//
//  DecodingErrorReporter.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Synchronization

/// Structured diagnostic payload captured when a `DecodingError` occurs.
public struct DecodingErrorDiagnostic: Codable, Sendable, Equatable {
    public let errorType: String
    public let schemaPath: String
    public let codingPath: [String]
    public let missingKey: String?
    public let expectedType: String?
    public let debugDescription: String
    public let message: String
    public let url: URL
    public let httpMethod: String
    public let timestamp: Date

    public init(
        errorType: String,
        schemaPath: String,
        codingPath: [String],
        missingKey: String? = nil,
        expectedType: String? = nil,
        debugDescription: String,
        message: String,
        url: URL,
        httpMethod: String,
        timestamp: Date = Date()
    ) {
        self.errorType = errorType
        self.schemaPath = schemaPath
        self.codingPath = codingPath
        self.missingKey = missingKey
        self.expectedType = expectedType
        self.debugDescription = debugDescription
        self.message = message
        self.url = url
        self.httpMethod = httpMethod
        self.timestamp = timestamp
    }
}

public enum DecodingErrorReporter {

    // Mutex is compiler-checked. The previous `nonisolated(unsafe)` + `NSLock`
    // pair encoded the same exclusive-access invariant by comment only (#1198).
    private static let handler = Mutex<(@Sendable (_ error: DecodingError, _ url: URL, _ httpMethod: String, _ message: String) -> Void)?>(nil)
    private static let structuredHandler = Mutex<(@Sendable (_ diagnostic: DecodingErrorDiagnostic) -> Void)?>(nil)

    public static var reportHandler: (@Sendable (_ error: DecodingError, _ url: URL, _ httpMethod: String, _ message: String) -> Void)? {
        get { handler.withLock { $0 } }
        set { handler.withLock { $0 = newValue } }
    }

    public static var diagnosticHandler: (@Sendable (_ diagnostic: DecodingErrorDiagnostic) -> Void)? {
        get { structuredHandler.withLock { $0 } }
        set { structuredHandler.withLock { $0 = newValue } }
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

    /// Redacts query parameters in a URL, replacing parameter values with `[REDACTED]`
    /// so sensitive tokens (e.g. key, token, apiKey) and coordinates (e.g. lat, lon) are sanitized,
    /// and clears any URL fragment (#1710 privacy policy).
    public static func redactURL(_ url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }
        components.fragment = nil
        guard let queryItems = components.queryItems, !queryItems.isEmpty else {
            return components.url ?? url
        }
        components.queryItems = queryItems.map { item in
            URLQueryItem(name: item.name, value: "[REDACTED]")
        }
        return components.url ?? url
    }

    /// Generates a structured `DecodingErrorDiagnostic` from a `DecodingError`.
    public static func diagnostic(
        for error: DecodingError,
        url: URL,
        httpMethod: String,
        date: Date = Date()
    ) -> DecodingErrorDiagnostic {
        let details = deconstruct(error)
        return DecodingErrorDiagnostic(
            errorType: details.errorType,
            schemaPath: details.schemaPath,
            codingPath: details.codingPath,
            missingKey: details.missingKey,
            expectedType: details.expectedType,
            debugDescription: details.debugDescription,
            message: message(from: error),
            url: redactURL(url),
            httpMethod: httpMethod,
            timestamp: date
        )
    }

    /// The legacy `reportHandler` gets `url` without its query, which holds the API key and
    /// sometimes the rider's coordinates (#1710).
    /// If configured, `diagnosticHandler` is invoked with a structured `DecodingErrorDiagnostic`.
    public static func report(error: DecodingError, url: URL, httpMethod: String) {
        let errorMessage = message(from: error)
        let legacyURL = ErrorReport.stripQuery(url)

        let legacyHandler = reportHandler
        let diagHandler = diagnosticHandler

        if legacyHandler == nil && diagHandler == nil {
            Logger.warn("Handler not configured. DecodingError not reported: \(legacyURL.absoluteString)")
            return
        }

        legacyHandler?(error, legacyURL, httpMethod, errorMessage)

        if let diagHandler {
            let diag = diagnostic(for: error, url: url, httpMethod: httpMethod)
            diagHandler(diag)
        }
    }

    private struct DeconstructedError {
        let errorType: String
        let codingPath: [String]
        let schemaPath: String
        let missingKey: String?
        let expectedType: String?
        let debugDescription: String
    }

    private static func deconstruct(_ error: DecodingError) -> DeconstructedError {
        switch error {
        case .keyNotFound(let key, let context):
            return DeconstructedError(
                errorType: "keyNotFound",
                codingPath: context.codingPath.map { $0.stringValue },
                schemaPath: path(context),
                missingKey: key.stringValue,
                expectedType: nil,
                debugDescription: context.debugDescription
            )
        case .typeMismatch(let type, let context):
            return DeconstructedError(
                errorType: "typeMismatch",
                codingPath: context.codingPath.map { $0.stringValue },
                schemaPath: path(context),
                missingKey: nil,
                expectedType: String(describing: type),
                debugDescription: context.debugDescription
            )
        case .valueNotFound(let type, let context):
            return DeconstructedError(
                errorType: "valueNotFound",
                codingPath: context.codingPath.map { $0.stringValue },
                schemaPath: path(context),
                missingKey: nil,
                expectedType: String(describing: type),
                debugDescription: context.debugDescription
            )
        case .dataCorrupted(let context):
            return DeconstructedError(
                errorType: "dataCorrupted",
                codingPath: context.codingPath.map { $0.stringValue },
                schemaPath: path(context),
                missingKey: nil,
                expectedType: nil,
                debugDescription: context.debugDescription
            )
        @unknown default:
            return DeconstructedError(
                errorType: "unknown",
                codingPath: [],
                schemaPath: "root",
                missingKey: nil,
                expectedType: nil,
                debugDescription: error.localizedDescription
            )
        }
    }

    private static func path(_ context: DecodingError.Context) -> String {
        context.codingPath.isEmpty
            ? "root"
            : context.codingPath.map { $0.stringValue }.joined(separator: " → ")
    }
}
