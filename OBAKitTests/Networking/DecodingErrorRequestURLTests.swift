//
//  DecodingErrorRequestURLTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreLocation
import Foundation
import Testing
@testable import OBAKitCore

/// #1589 follow-up: Problem Details showed no request URL when a response
/// arrived but didn't decode, because the decode rethrew the bare error.
@Suite(.serialized)
final class DecodingErrorRequestURLTests: OBATestCase {

    @Test func `A response that doesn't decode reaches the report with its request URL`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        let body = #"{"code":200,"currentTime":0,"text":"OK","version":2,"data":{"limitExceeded":false,"list":7,"references":{}}}"#
        dataLoader.mock(data: Data(body.utf8)) { request in
            request.url?.path.hasSuffix("/stops-for-location.json") ?? false
        }
        let service = buildRESTService(dataLoader: dataLoader)

        do {
            _ = try await service.getStops(coordinate: CLLocationCoordinate2D(latitude: 47.6, longitude: -122.3))
            Issue.record("Expected the stops to fail to decode")
        } catch {
            #expect(error is DecodingError, "Still a DecodingError, so callers matching on it still match")
            let report = ErrorReport(error: error, regionName: "Puget Sound", systemVersion: "26.1", deviceModel: "iPhone16,1")
            #expect(report.requestURL?.path.hasSuffix("/stops-for-location.json") == true)
            #expect(report.requestURL?.query == nil, "The API key stays out of the report")
        }
    }
}
