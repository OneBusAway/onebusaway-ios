//
//  RESTDataDecoder.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 5/24/19.
//

import Foundation

struct FieldError: LocalizedError {
    let message: String

    var errorDescription: String? { message }
    var failureReason: String? { nil }
    var recoverySuggestion: String? { nil }
    var helpAnchor: String? { nil }
}

/// Decodes raw `Data` from the REST API into a list of API `entries` and `references`.
public class RESTDataDecoder: NSObject {

    /// The raw data passed in at object creation.
    public let data: Data

    /// Deserialized JSON version of `data`.
    public let decodedJSONBody: Any?

    public let fieldErrors: [LocalizedError]?

    /// A list of entries from the `decodedJSONBody`.
    ///
    /// - Note: The REST API sends back either a single entry or a list, depending on the
    ///         endpoint. The `entries` field normalizes this behavior and presents everything
    ///         as a list.
    public private(set) var entries: [[String: Any]]?

    /// A list of references, from the `decodedJSONBody`.
    public private(set) var references: [String: Any]?

    /// Creates the RESTDataDecoder from a `data` object.
    ///
    /// - Parameter data: The raw output from a REST API endpoint.
    public init(data: Data) throws {
        self.data = data

        self.decodedJSONBody = try JSONSerialization.jsonObject(with: self.data, options: [])

        if let fieldErrors = RESTDataDecoder.decodeFieldErrors(from: decodedJSONBody) {
            self.fieldErrors = fieldErrors
        }
        else {
            self.fieldErrors = nil
        }

        if let (entries, references) = RESTDataDecoder.decodeEntriesAndReferences(from: decodedJSONBody) {
            self.entries = entries
            self.references = references
        }
        else {
            self.entries = nil
            self.references = nil
        }
    }

    /// Decodes `"fieldErrors"` data in the response body, if it exists.
    /// - Parameter decodedJSONBody: The decoded JSON body of the REST API response.
    ///
    /// Example body:
    ///
    /// ```
    /// { "fieldErrors": {
    ///     "lon": [ "Invalid field value for field \"lon\"." ]
    ///   }
    /// }
    /// ```
    private class func decodeFieldErrors(from decodedJSONBody: Any?) -> [FieldError]? {
        guard
            let dict = decodedJSONBody as? NSDictionary,
            let dataField = dict["fieldErrors"] as? NSDictionary
        else {
            return nil
        }

        var allErrors = [FieldError]()

        for (_, v) in dataField {
            if let rawErrors = v as? [String] {
                allErrors.append(contentsOf: rawErrors.compactMap({ FieldError(message: $0) }))
            }
            else if let rawError = v as? String {
                allErrors.append(FieldError(message: rawError))
            }
        }

        return allErrors
    }

    private class func decodeEntriesAndReferences(from decodedJSONBody: Any?) -> (entries: [[String: Any]]?, references: [String: Any]?)? {
        guard
            let dict = decodedJSONBody as? NSDictionary,
            let dataField = dict["data"] as? NSDictionary
        else {
            return nil
        }

        var entries: [[String: Any]]?

        if let entry = dataField["entry"] as? [String: Any] {
            entries = [entry]
        }
        else if let list = (dataField["list"] as? [[String: Any]]) {
            entries = list
        }

        var references: [String: Any]?

        if let refs = dataField["references"] {
            references = (refs as! [String: Any]) // swiftlint:disable:this force_cast
        }

        return (entries, references)
    }
}
