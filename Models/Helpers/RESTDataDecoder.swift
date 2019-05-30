//
//  RESTDataDecoder.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 5/24/19.
//

import Foundation

/// Decodes raw `Data` from the REST API into a list of API `entries` and `references`.
public class RESTDataDecoder: NSObject {

    /// The raw data passed in at object creation.
    public let data: Data

    /// Deserialized JSON version of `data`.
    public let decodedJSONBody: Any?

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

        self.decodedJSONBody = try JSONSerialization.jsonObject(with: self.data, options: [])// as! NSObject

        if let (entries, references) = RESTDataDecoder.decodeEntriesAndReferences(from: self.decodedJSONBody) {
            self.entries = entries
            self.references = references
        }
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
