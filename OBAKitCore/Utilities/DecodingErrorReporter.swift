//
//  DecodingErrorReporter.swift
//  OBAKit
//
//  Created by Divesh Patil on 16/01/26.
//
import Foundation

enum DecodingErrorReporter {

    static func message(from error: DecodingError) -> String {
        switch error {
        case .keyNotFound(let key, let context):
            return "Missing key: \(key.stringValue)\nPath: \(path(context))"

        case .typeMismatch(let type, let context):
            return "Type mismatch: \(type)\nPath: \(path(context))"

        case .valueNotFound(let type, let context):
            return "Missing value: \(type)\nPath: \(path(context))"

        case .dataCorrupted(let context):
            return "Data corrupted: \(context.debugDescription)"

        @unknown default:
            return "Unknown decoding error"
        }
    }

    private static func path(_ context: DecodingError.Context) -> String {
        context.codingPath.map { $0.stringValue }.joined(separator: " → ")
    }
}
