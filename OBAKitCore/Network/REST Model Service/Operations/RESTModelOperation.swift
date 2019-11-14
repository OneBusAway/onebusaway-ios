//
//  RESTModelOperation.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 10/20/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import Foundation
import CocoaLumberjackSwift

/// Base class for model operations that deal with the OBA REST API.
public class RESTModelOperation: Operation {
    public var apiOperation: RESTAPIOperation?
    public private(set) var references: References?

    required public override init() {
        super.init()
    }

    override public func main() {
        if let references = apiOperation?.references {
            do {
                self.references = try References.decodeReferences(references)
            }
            catch {
                DDLogError("Unable to decode references from data: \(error)")
            }
        }
    }

    // MARK: - Errors

    /// Returns `true` if this operation has returned an error on data retrieval or decode.
    public var hasError: Bool {
        if error != nil {
            return true
        }
        else if let fieldErrors = fieldErrors {
            return fieldErrors.count > 0
        }
        else {
            return false
        }
    }

    public var error: Error? {
        apiOperation?.error
    }

    public var fieldErrors: [LocalizedError]? {
        apiOperation?.fieldErrors
    }

    // MARK: - Decoder Helpers

    func decodeModels<T>(type: T.Type) -> [T] where T: Decodable {
        guard let entries = apiOperation?.entries else {
            return []
        }

        var models = [T]()

        do {
            models = try DictionaryDecoder.decodeModels(entries, references: references, type: type)
        }
        catch {
            DDLogError("Unable to decode models from data: \(error)")
        }

        return models
    }

    // MARK: - Debugging

    public override var debugDescription: String {
        let urlString = apiOperation?.request.url?.absoluteString ?? ""
        return "\(super.debugDescription) - URL: \(urlString)"
    }
}
