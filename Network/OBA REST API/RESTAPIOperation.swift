//
//  RESTAPIOperation.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 1/22/19.
//  Copyright © 2019 OneBusAway. All rights reserved.
//

import Foundation

/// The core API operation class for the OBA REST API.
///
/// - Note: An `error` with Domain=NSCocoaErrorDomain, Code=3840 usually means that you're hitting a captive portal.
///
@objc(OBARESTAPIOperation)
public class RESTAPIOperation: NetworkOperation {
    public var entries: [[String: Any]]? {
        return restDecoder?.entries
    }

    public var references: [String: Any]? {
        return restDecoder?.references
    }

    /// Only available after `-setData:response:error:` is called.
    internal var restDecoder: RESTDataDecoder?

    /// The full JSON body decoded from `data`. Only available after `-setData:response:error:` is called.
    internal var decodedJSONBody: Any? {
        return restDecoder?.decodedJSONBody
    }

    /// Override this method in order to perform data-shaping after the raw data has been loaded.
    internal func dataFieldsDidSet() {
        // nop
    }

    override func set(data: Data?, response: HTTPURLResponse?, error: Error?) {
        super.set(data: data, response: response, error: error)

        guard let data = data else {
            return
        }

        do {
            self.restDecoder = try RESTDataDecoder(data: data)
        } catch let error {
            self.error = error
            return
        }

        if
            let dict = self.restDecoder?.decodedJSONBody as? NSDictionary,
            let url = response?.url,
            let code = dict["code"] as? NSNumber,
            let headerFields = response?.allHeaderFields as? [String: String] {
            self.response = HTTPURLResponse(url: url, statusCode: code.intValue, httpVersion: nil, headerFields: headerFields)
        }

        dataFieldsDidSet()
    }
}
