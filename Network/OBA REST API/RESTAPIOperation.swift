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
    public private(set) var entries: [[String: Any]]?
    public private(set) var references: [String: Any]?

    /// The full JSON body decoded from `data`. Only available after `-setData:response:error:` is called.
    internal private(set) var _decodedJSONBody: Any?

    /// Override this method in order to perform data-shaping after the raw data has been loaded.
    internal func _dataFieldsDidSet() {
        // nop
    }

    override func set(data: Data?, response: HTTPURLResponse?, error: Error?) {
        super.set(data: data, response: response, error: error)

        guard let data = data else {
            return
        }

        var jsonError: Error?

        do {
            _decodedJSONBody = try JSONSerialization.jsonObject(with: data, options: []) as! NSObject
        } catch {
            self.error = error
            return
        }

        defer {
            _dataFieldsDidSet()
        }

        guard
            let dict = _decodedJSONBody as? NSDictionary,
            let url = response?.url,
            let code = dict["code"] as? NSNumber,
            let headerFields = response?.allHeaderFields as? [String: String]
        else {
            return
        }

        let statusCode = code.intValue

        self.response = HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: nil, headerFields: headerFields)

        guard let dataField = dict["data"] as? NSDictionary else {
            return
        }

        if let entry = dataField["entry"] {
            entries = [entry] as? [[String : Any]]
        }
        else if let list = (dataField["list"] as? [[String : Any]]) {
            entries = list
        }

        if let refs = dataField["references"] {
            references = (refs as! [String : Any])
        }
    }
}
