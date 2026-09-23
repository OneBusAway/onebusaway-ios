//
//  RegionsAPIServiceStandaloneTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
@testable import OBAKit
@testable import OBAKitCore

@Suite(.serialized)
final class RegionsAPIServiceStandaloneTests: OBATestCase {

    @Test func `Standalone service fetches the regions list through the injected loader`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        stubRegions(dataLoader: dataLoader)

        let service = RegionsAPIService.standalone(
            baseURL: regionsURL,
            apiKey: apiKey,
            appVersion: appVersion,
            uuid: uuid,
            dataLoader: dataLoader
        )

        let regions = try await service.getRegions(apiPath: regionsAPIPath).list

        #expect(regions.count > 1)
        #expect(regions.contains { $0.name == "Puget Sound" })
    }

    @Test func `Standalone service sends the app identity as query items`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        stubRegions(dataLoader: dataLoader)

        let service = RegionsAPIService.standalone(
            baseURL: regionsURL,
            apiKey: apiKey,
            appVersion: appVersion,
            uuid: uuid,
            dataLoader: dataLoader
        )
        _ = try await service.getRegions(apiPath: regionsAPIPath)

        let url = try #require(dataLoader.recordedRequestURLs.first)
        let query = try #require(url.query)
        #expect(query.contains("key=\(apiKey)"))
        #expect(query.contains("app_uid=\(uuid)"))
        #expect(query.contains("app_ver=\(appVersion)"))
    }
}
