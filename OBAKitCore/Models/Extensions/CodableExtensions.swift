//
//  CodableExtensions.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 5/30/19.
//

import Foundation

extension KeyedDecodingContainer {

    /// Decodes an optional URL where the underlying value may either be
    /// nil, a blank string, or a valid URL, for the given key, if present.
    ///
    /// This method returns `nil` if the container does not have a value
    /// associated with `key`, or if the value is null or garbage (e.g. a blank string). The difference between
    /// these states can be distinguished with a `contains(_:)` call.
    ///
    /// - parameter key: The key that the decoded value is associated with.
    /// - returns: A decoded value of the requested type, or `nil` if the
    ///   `Decoder` does not have an entry associated with the given key, or if
    ///   the value is a null value.
    /// - throws: `DecodingError.typeMismatch` if the encountered encoded value
    ///   is not convertible to `String`.
    func decodeGarbageURL(forKey key: Self.Key) throws -> URL? {
        var rawStr: String?
        do {
            rawStr = try decodeIfPresent(String.self, forKey: key)
        } catch let err {
            print("Error: \(err)")
            throw err
        }
        guard let urlString = ModelHelpers.nilifyBlankValue(rawStr) else {
            return nil
        }
        return URL(string: urlString)
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

//    /// Loads JSON data from the specified file name in the bundle, and creates a model or models of `type` from the JSON.
//    /// - Parameter type: The model type
//    /// - Parameter fileName: The name of the file in the test bundle that contains the JSON data.
//    /// - Parameter skipReferences: Don't try decoding references. Used for Regions.
//    /// - Returns: A decoded array of models.
//    /// - Throws: Errors in case of a decoding failure.
//    static func decodeFromFile(named fileName: String, in bundle: Bundle = .main, skipReferences: Bool = false) throws -> [Self] {
//        let json = try loadJSONDictionary(file: fileName, in: bundle)
//        return try decodeModels(json: json, skipReferences: skipReferences)
//    }

    /// Decodes models of `type` from the supplied JSON.
    /// The JSON should be the full contents of a server response, including References.
    ///
    /// - Parameters:
    ///   - type: The model type
    ///   - json: The JSON data to decode from.
    ///   - skipReferences: Don't try decoding references. Used for Regions.
    /// - Returns: A decoded array of models.
    /// - Throws: Errors in case of a decoding failure.
//    private static func decodeModels(json: [String: Any], skipReferences: Bool = false) throws -> [Self] {
//        guard let data = json["data"] as? [String: Any] else {
//            throw DecodableError.invalidData
//        }
//
//        let decodedReferences: References?
//
//        if skipReferences {
//            decodedReferences = nil
//        }
//        else {
//            guard let references = data["references"] as? [String: Any] else {
//                throw DecodableError.invalidReferences
//            }
//
//            decodedReferences = try References.decodeReferences(references)
//        }
//
//        let modelDicts: [[String: Any]]
//        if let list = data["list"] as? [[String: Any]] {
//            modelDicts = list
//        }
//        else if let entry = data["entry"] as? [String: Any] {
//            modelDicts = [entry]
//        }
//        else {
//            throw DecodableError.invalidModelList
//        }
//
//        let models = try DictionaryDecoder.decodeModels(modelDicts, references: decodedReferences, type: self)
//
//        return models
//    }
}
