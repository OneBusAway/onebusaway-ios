//
//  ErrorClassifierTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import XCTest
import Nimble
@testable import OBAKitCore

class ErrorClassifierTests: XCTestCase {

    // MARK: - APIError Pass-Through

    func test_classify_captivePortal_passesThrough() {
        let error = APIError.captivePortal
        let result = ErrorClassifier.classify(error, regionName: "Puget Sound")

        guard let apiError = result as? APIError else {
            fail("Expected APIError, got \(type(of: result))")
            return
        }

        switch apiError {
        case .captivePortal:
            break // Expected
        default:
            fail("Expected .captivePortal, got \(apiError)")
        }
    }

    func test_classify_requestNotFound_passesThrough() {
        let url = URL(string: "https://api.pugetsound.onebusaway.org/api/where/stop/1_75403.json")!
        let response = HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!
        let error = APIError.requestNotFound(response)
        let result = ErrorClassifier.classify(error, regionName: "Puget Sound")

        guard let apiError = result as? APIError else {
            fail("Expected APIError, got \(type(of: result))")
            return
        }

        switch apiError {
        case .requestNotFound:
            break // Expected — 404s should not become serverUnavailable
        default:
            fail("Expected .requestNotFound, got \(apiError)")
        }
    }

    func test_classify_noResponseBody_passesThrough() {
        let error = APIError.noResponseBody
        let result = ErrorClassifier.classify(error, regionName: "Puget Sound")

        guard let apiError = result as? APIError else {
            fail("Expected APIError, got \(type(of: result))")
            return
        }

        switch apiError {
        case .noResponseBody:
            break // Expected
        default:
            fail("Expected .noResponseBody, got \(apiError)")
        }
    }

    // MARK: - Server Error Upgrade (5xx → serverUnavailable)

    func test_classify_requestFailure500_becomesServerUnavailable() {
        let url = URL(string: "https://api.pugetsound.onebusaway.org/api/where/stops.json")!
        let response = HTTPURLResponse(url: url, statusCode: 500, httpVersion: nil, headerFields: nil)!
        let error = APIError.requestFailure(response)
        let result = ErrorClassifier.classify(error, regionName: "Puget Sound")

        guard let apiError = result as? APIError else {
            fail("Expected APIError, got \(type(of: result))")
            return
        }

        switch apiError {
        case .serverUnavailable(let regionName, let statusCode):
            expect(regionName) == "Puget Sound"
            expect(statusCode) == 500
        default:
            fail("Expected .serverUnavailable, got \(apiError)")
        }
    }

    func test_classify_requestFailure503_becomesServerUnavailable() {
        let url = URL(string: "https://api.pugetsound.onebusaway.org/api/where/stops.json")!
        let response = HTTPURLResponse(url: url, statusCode: 503, httpVersion: nil, headerFields: nil)!
        let error = APIError.requestFailure(response)
        let result = ErrorClassifier.classify(error, regionName: "Tampa")

        guard let apiError = result as? APIError else {
            fail("Expected APIError, got \(type(of: result))")
            return
        }

        switch apiError {
        case .serverUnavailable(let regionName, let statusCode):
            expect(regionName) == "Tampa"
            expect(statusCode) == 503
        default:
            fail("Expected .serverUnavailable, got \(apiError)")
        }
    }

    func test_classify_requestFailure500_withoutRegionName_staysAsRequestFailure() {
        let url = URL(string: "https://api.pugetsound.onebusaway.org/api/where/stops.json")!
        let response = HTTPURLResponse(url: url, statusCode: 500, httpVersion: nil, headerFields: nil)!
        let error = APIError.requestFailure(response)
        let result = ErrorClassifier.classify(error, regionName: nil)

        guard let apiError = result as? APIError else {
            fail("Expected APIError, got \(type(of: result))")
            return
        }

        switch apiError {
        case .requestFailure(let resp):
            expect(resp.statusCode) == 500
        default:
            fail("Expected .requestFailure to pass through when regionName is nil, got \(apiError)")
        }
    }

    func test_classify_requestFailure400_doesNotBecomeServerUnavailable() {
        let url = URL(string: "https://api.pugetsound.onebusaway.org/api/where/stops.json")!
        let response = HTTPURLResponse(url: url, statusCode: 400, httpVersion: nil, headerFields: nil)!
        let error = APIError.requestFailure(response)
        let result = ErrorClassifier.classify(error, regionName: "Puget Sound")

        guard let apiError = result as? APIError else {
            fail("Expected APIError, got \(type(of: result))")
            return
        }

        // 4xx errors are client errors, not server-down situations.
        switch apiError {
        case .requestFailure(let resp):
            expect(resp.statusCode) == 400
        default:
            fail("Expected .requestFailure for 4xx, got \(apiError)")
        }
    }

    // MARK: - DecodingError Classification

    func test_classify_decodingError_withRegionName_becomesServerUnavailable() {
        let decodingError = DecodingError.keyNotFound(
            AnyCodingKey(stringValue: "data")!,
            DecodingError.Context(codingPath: [], debugDescription: "No value associated with key")
        )
        let result = ErrorClassifier.classify(decodingError, regionName: "San Diego")

        guard let apiError = result as? APIError else {
            fail("Expected APIError, got \(type(of: result))")
            return
        }

        switch apiError {
        case .serverUnavailable(let regionName, let statusCode):
            expect(regionName) == "San Diego"
            expect(statusCode).to(beNil())
        default:
            fail("Expected .serverUnavailable, got \(apiError)")
        }
    }

    func test_classify_decodingError_withoutRegionName_returnsUserFriendlyError() {
        let decodingError = DecodingError.dataCorrupted(
            DecodingError.Context(codingPath: [], debugDescription: "The given data was not valid JSON.")
        )
        let result = ErrorClassifier.classify(decodingError, regionName: nil)

        // Should NOT be the raw "The data couldn't be read because it is missing."
        let description = result.localizedDescription
        expect(description).toNot(contain("couldn't be read"))
        expect(description).to(contain("server"))
    }

    // MARK: - NSURLError Classification

    func test_classify_urlErrorTimedOut_withRegionName_becomesServerUnavailable() {
        let urlError = NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut, userInfo: nil)
        let result = ErrorClassifier.classify(urlError, regionName: "York Region")

        guard let apiError = result as? APIError else {
            fail("Expected APIError, got \(type(of: result))")
            return
        }

        switch apiError {
        case .serverUnavailable(let regionName, _):
            expect(regionName) == "York Region"
        default:
            fail("Expected .serverUnavailable for timeout, got \(apiError)")
        }
    }

    func test_classify_urlErrorCannotConnectToHost_withRegionName_becomesServerUnavailable() {
        let urlError = NSError(domain: NSURLErrorDomain, code: NSURLErrorCannotConnectToHost, userInfo: nil)
        let result = ErrorClassifier.classify(urlError, regionName: "Tampa")

        guard let apiError = result as? APIError else {
            fail("Expected APIError, got \(type(of: result))")
            return
        }

        switch apiError {
        case .serverUnavailable(let regionName, _):
            expect(regionName) == "Tampa"
        default:
            fail("Expected .serverUnavailable, got \(apiError)")
        }
    }

    func test_classify_urlErrorTimedOut_withoutRegionName_becomesNetworkFailure() {
        let urlError = NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut, userInfo: nil)
        let result = ErrorClassifier.classify(urlError, regionName: nil)

        guard let apiError = result as? APIError else {
            fail("Expected APIError, got \(type(of: result))")
            return
        }

        switch apiError {
        case .networkFailure:
            break // Expected fallback when no region name
        default:
            fail("Expected .networkFailure when regionName is nil, got \(apiError)")
        }
    }

    func test_classify_urlErrorNotConnectedToInternet_becomesNetworkFailure() {
        // When cellular data is NOT restricted, this should be a generic network failure.
        // Note: We can't reliably mock CTCellularData.restrictedState in unit tests,
        // so we verify the non-restricted path here. On a simulator, cellular is
        // typically not restricted.
        let urlError = NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet, userInfo: nil)
        let result = ErrorClassifier.classify(urlError, regionName: "Puget Sound")

        guard let apiError = result as? APIError else {
            fail("Expected APIError, got \(type(of: result))")
            return
        }

        // On simulators, isCellularDataRestricted is typically false,
        // so this should classify as networkFailure.
        switch apiError {
        case .networkFailure, .cellularDataRestricted:
            break // Either is acceptable depending on simulator state
        default:
            fail("Expected .networkFailure or .cellularDataRestricted, got \(apiError)")
        }
    }

    func test_classify_urlErrorUnknownCode_becomesNetworkFailure() {
        let urlError = NSError(domain: NSURLErrorDomain, code: NSURLErrorUnknown, userInfo: nil)
        let result = ErrorClassifier.classify(urlError, regionName: "Puget Sound")

        guard let apiError = result as? APIError else {
            fail("Expected APIError, got \(type(of: result))")
            return
        }

        switch apiError {
        case .networkFailure:
            break // Expected
        default:
            fail("Expected .networkFailure for unknown URL error, got \(apiError)")
        }
    }

    // MARK: - Non-Network Errors Pass Through

    func test_classify_arbitraryError_passesThrough() {
        let error = NSError(domain: "com.example.test", code: 42, userInfo: [
            NSLocalizedDescriptionKey: "Something unrelated happened"
        ])
        let result = ErrorClassifier.classify(error, regionName: "Puget Sound")

        expect(result.localizedDescription) == "Something unrelated happened"
    }

    // MARK: - serverUnavailable Error Description

    func test_serverUnavailable_errorDescription_containsRegionName() {
        let error = APIError.serverUnavailable(regionName: "Puget Sound", statusCode: 502)
        let description = error.localizedDescription

        expect(description).to(contain("Puget Sound"))
        expect(description).to(contain("down"))
    }

    func test_cellularDataRestricted_errorDescription_mentionsSettings() {
        let error = APIError.cellularDataRestricted
        let description = error.localizedDescription

        expect(description).to(contain("Settings"))
        expect(description).to(contain("Cellular"))
    }
}

// MARK: - Test Helpers

/// A simple CodingKey implementation for creating test DecodingErrors.
private struct AnyCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }
}
