//
//  OBAKitCoreTestCase.swift
//  OBAKitCoreTests
// 
//  Copyright © 2023 Open Transit Software Foundation.
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import XCTest
import OBAKitCore

final class Fixtures {
    static func loadData(file: String) throws -> Data {
        let testBundle = Bundle(for: self)
        let url = try XCTUnwrap(testBundle.path(forResource: file, ofType: nil), "Cannot find fixture \(file)")

        return try Data(contentsOf: URL(fileURLWithPath: url), options: .mappedIfSafe)
    }
}

open class OBAKitCoreTestCase: XCTestCase {
    var restAPIService: RESTAPIService!
    var dataLoader: MockDataLoader!

    override open func setUp() async throws {
        try await super.setUp()

        let configuration = APIServiceConfiguration(
            baseURL: URL(string: "https://www.example.com")!,
            apiKey: "API_KEY",
            uuid: "UUID",
            appVersion: "1.0.0",
            regionIdentifier: 1
        )

        dataLoader = MockDataLoader(testName: self.name)
        restAPIService = RESTAPIService(configuration, dataLoader: dataLoader)
    }
}
