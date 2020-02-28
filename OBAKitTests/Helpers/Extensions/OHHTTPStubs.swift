//
//  OHHTTPStubs.swift
//  OBAKitTests
//
//  Created by Aaron Brethorst on 8/17/19.
//

import Foundation
import OHHTTPStubs

public extension OHHTTPStubsResponse {
    class func dataFile(named name: String) -> OHHTTPStubsResponse {
        return file(named: name, contentType: "application/octet-stream")
    }

    class func JSONFile(named name: String) -> OHHTTPStubsResponse {
        return file(named: name, contentType: "application/json")
    }

    class func file(named name: String, contentType: String, statusCode: Int = 200) -> OHHTTPStubsResponse {
        guard let path = Bundle(for: OBATestCase.self).path(forResource: name, ofType: nil) else {
            fatalError()
        }
        return OHHTTPStubsResponse(
            fileAtPath: path,
            statusCode: Int32(statusCode),
            headers: ["Content-Type": contentType]
        )
    }
}
