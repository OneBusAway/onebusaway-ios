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
        return OHHTTPStubsResponse(
            fileAtPath: OHPathForFile(name, OBATestCase.self)!,
            statusCode: Int32(statusCode),
            headers: ["Content-Type": contentType]
        )
    }
}
