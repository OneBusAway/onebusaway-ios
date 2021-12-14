//
//  RESTAPIResponse.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

/// Represents the most simple type of response from the OBA REST API.
///
/// This class is used to model the server responses for requests like getting the current time or reporting stop or trip
/// problems. Responses that lack a `list` or `entry` key in their response body are represented by this class.
public class CoreRESTAPIResponse: NSObject, Decodable {
    public let code: Int
    public let currentTime: Int?
    public let text: String?
    public let version: Int

    fileprivate enum CodingKeys: String, CodingKey {
        case code, currentTime, data, text, version
    }

    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        code = try container.decode(Int.self, forKey: .code)
        currentTime = try container.decodeIfPresent(Int.self, forKey: .currentTime)
        text = try container.decodeIfPresent(String.self, forKey: .text)
        version = try container.decode(Int.self, forKey: .version)
    }
}

/// Represents an OBA REST API server response that includes a payload of one or more model objects.
///
/// This class is used to model server responses for requests like retrieving a list of stops or trip details.
public class RESTAPIResponse<T>: CoreRESTAPIResponse where T: Decodable {
    public let limitExceeded: Bool?
    public let outOfRange: Bool?
    public let references: References?

    /// The decoded data model or models.
    ///
    /// - Note: This value is identical to `entry`. You should use whichever property feels more 'ergonomic' for your use case.
    public let list: T

    /// The decoded data model or models.
    ///
    /// - Note: This value is identical to `list`. You should use whichever property feels more 'ergonomic' for your use case.
    public var entry: T { list }

    private enum DataCodingKeys: String, CodingKey {
        case data, limitExceeded, entry, list, outOfRange, references
    }

    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Data Field
        let dataContainer = try container.nestedContainer(keyedBy: DataCodingKeys.self, forKey: .data)

        if let entry = try dataContainer.decodeIfPresent(T.self, forKey: .entry) {
            list = entry
        }
        else {
            list = try dataContainer.decode(T.self, forKey: .list)
        }

        references = try dataContainer.decodeIfPresent(References.self, forKey: .references)

        let regionIdentifier = decoder.userInfo[References.regionIdentifierUserInfoKey] as? Int

        if let list = list as? HasReferences, let references = references {
            list.loadReferences(references, regionIdentifier: regionIdentifier)
        }

        limitExceeded = try dataContainer.decodeIfPresent(Bool.self, forKey: .limitExceeded)
        outOfRange = try dataContainer.decodeIfPresent(Bool.self, forKey: .outOfRange)

        try super.init(from: decoder)
    }
}
