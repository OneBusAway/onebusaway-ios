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
public class RESTAPIOperation: NetworkOperation {

    /// `"entries"` API data
    public var entries: [[String: Any]]? {
        return restDecoder?.entries
    }

    /// `"references"` API data
    public var references: [String: Any]? {
        return restDecoder?.references
    }

    /// `"fieldErrors"` API data
    public var fieldErrors: [Error]? {
        restDecoder?.fieldErrors
    }

    /// Only available after `-setData:response:error:` is called.
    var restDecoder: RESTDataDecoder?

    /// The full JSON body decoded from `data`. Only available after `-setData:response:error:` is called.
    var decodedJSONBody: Any? {
        return restDecoder?.decodedJSONBody
    }

    /// Override this method in order to perform data-shaping after the raw data has been loaded.
    func dataFieldsDidSet() {
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

        self.response = buildMungedHTTPURLResponse(jsonBody: self.restDecoder?.decodedJSONBody, response: response)

        dataFieldsDidSet()
    }

    /// Creates a 'normalized' `HTTPURLResponse` object that contains the response's real status code,
    /// as contained within the response body's `code` field, as opposed to the 200 that the REST API
    /// always returns.
    ///
    /// - Parameters:
    ///   - jsonBody: The decoded response body. Although the type here is `Any?`, it is expected to be a dictionary.
    ///   - response: The full, original response.
    /// - Returns: An `HTTPURLResponse` with a correct status code, if it is possible to create it.
    private func buildMungedHTTPURLResponse(jsonBody: Any?, response: HTTPURLResponse?) -> HTTPURLResponse? {
        guard
            let dict = jsonBody as? NSDictionary,
            let code = dict["code"] as? NSNumber,
            let url = response?.url,
            let headerFields = response?.allHeaderFields as? [String: String]
        else {
            return nil
        }

        return HTTPURLResponse(url: url, statusCode: code.intValue, httpVersion: nil, headerFields: headerFields)
    }
}
