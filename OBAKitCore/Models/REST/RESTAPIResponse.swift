//
//  RESTAPIResponse.swift
//  OBAKitCore
//
//  Created by Aaron Brethorst on 4/24/20.
//

import Foundation

public class CoreRESTAPIResponse: NSObject, Decodable {
    public let code: Int
    public let currentTime: Int?
    public let text: String
    public let version: Int

    fileprivate enum CodingKeys: String, CodingKey {
        case code, currentTime, data, text, version
    }

    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        code = try container.decode(Int.self, forKey: .code)
        currentTime = try container.decodeIfPresent(Int.self, forKey: .currentTime)
        text = try container.decode(String.self, forKey: .text)
        version = try container.decode(Int.self, forKey: .version)
    }
}

public class RESTAPIResponse<T>: CoreRESTAPIResponse where T: Decodable {
    public let limitExceeded: Bool?
    public let list: T
    public let outOfRange: Bool?
    public let references: References?

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

        if let list = list as? HasReferences, let references = references {
            list.loadReferences(references)
        }

        limitExceeded = try dataContainer.decodeIfPresent(Bool.self, forKey: .limitExceeded)
        outOfRange = try dataContainer.decodeIfPresent(Bool.self, forKey: .outOfRange)

        try super.init(from: decoder)
    }
}
