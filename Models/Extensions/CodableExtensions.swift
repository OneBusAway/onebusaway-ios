//
//  CodableExtensions.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 5/30/19.
//

import Foundation

// MARK: - Decoder

extension Decoder {
    /// Convenience accessor for retrieving `References` objects plumbed in via the `userInfo` property.
    var references: References {
        return userInfo[CodingUserInfoKey.references] as! References // swiftlint:disable:this force_cast
    }
}

// MARK: - Decodable

public enum DecodableError: Error {
    case invalidData, invalidModelList, invalidReferences, missingFile
}

public extension Decodable {
    private static func loadJSONDictionary(file: String, in bundle: Bundle) throws -> [String: Any] {
        guard let path = bundle.path(forResource: file, ofType: nil) else {
            throw DecodableError.missingFile
        }
        let data = NSData(contentsOfFile: path)! as Data
        let json = try JSONSerialization.jsonObject(with: data, options: [])

        return (json as! [String: Any]) // swiftlint:disable:this force_cast
    }

    /// Loads JSON data from the specified file name in the bundle, and creates a model or models of `type` from the JSON.
    /// - Parameter type: The model type
    /// - Parameter fileName: The name of the file in the test bundle that contains the JSON data.
    /// - Parameter skipReferences: Don't try decoding references. Used for Regions.
    /// - Returns: A decoded array of models.
    /// - Throws: Errors in case of a decoding failure.
    static func decodeFromFile(named fileName: String, in bundle: Bundle = .main, skipReferences: Bool = false) throws -> [Self] {
        let json = try loadJSONDictionary(file: fileName, in: bundle)
        return try decodeModels(json: json, skipReferences: skipReferences)
    }

    /// Decodes models of `type` from the supplied JSON.
    /// The JSON should be the full contents of a server response, including References.
    ///
    /// - Parameters:
    ///   - type: The model type
    ///   - json: The JSON data to decode from.
    ///   - skipReferences: Don't try decoding references. Used for Regions.
    /// - Returns: A decoded array of models.
    /// - Throws: Errors in case of a decoding failure.
    private static func decodeModels(json: [String: Any], skipReferences: Bool = false) throws -> [Self] {
        guard let data = json["data"] as? [String: Any] else {
            throw DecodableError.invalidData
        }

        let decodedReferences: References?

        if skipReferences {
            decodedReferences = nil
        }
        else {
            guard let references = data["references"] as? [String: Any] else {
                throw DecodableError.invalidReferences
            }

            decodedReferences = try References.decodeReferences(references)
        }

        let modelDicts: [[String: Any]]
        if let list = data["list"] as? [[String: Any]] {
            modelDicts = list
        }
        else if let entry = data["entry"] as? [String: Any] {
            modelDicts = [entry]
        }
        else {
            throw DecodableError.invalidModelList
        }

        let models = try DictionaryDecoder.decodeModels(modelDicts, references: decodedReferences, type: self)

        return models
    }
}
