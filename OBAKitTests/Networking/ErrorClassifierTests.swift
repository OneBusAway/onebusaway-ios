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
            break
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
            break
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
            break
        default:
            fail("Expected .noResponseBody, got \(apiError)")
        }
    }

    func test_classify_invalidContentType_passesThrough() {
        let error = APIError.invalidContentType(
            originalError: nil,
            expectedContentType: "application/json",
            actualContentType: "text/html"
        )
        let result = ErrorClassifier.classify(error, regionName: "Puget Sound")

        guard let apiError = result as? APIError else {
            fail("Expected APIError, got \(type(of: result))")
            return
        }

        switch apiError {
        case .invalidContentType:
            break
        default:
            fail("Expected .invalidContentType, got \(apiError)")
        }
    }

    // MARK: - Server Error Classification (500 vs other 5xx)

    func test_classify_requestFailure500_becomesServerError() {
        let url = URL(string: "https://api.pugetsound.onebusaway.org/api/where/stops.json")!
        let response = HTTPURLResponse(url: url, statusCode: 500, httpVersion: nil, headerFields: nil)!
        let error = APIError.requestFailure(response)
        let result = ErrorClassifier.classify(error, regionName: "Puget Sound")

        guard let apiError = result as? APIError else {
            fail("Expected APIError, got \(type(of: result))")
            return
        }

        switch apiError {
        case .serverError(let regionName):
            expect(regionName) == "Puget Sound"
        default:
            fail("Expected .serverError, got \(apiError)")
        }
    }

    func test_serverError_errorDescription_suggestsRetry() {
        let error = APIError.serverError(regionName: "Puget Sound")
        let description = error.localizedDescription

        expect(description).to(contain("Puget Sound"))
        expect(description).to(contain("try again"))
    }

    func test_classify_requestFailure502_becomesServerUnavailable() {
        let url = URL(string: "https://api.pugetsound.onebusaway.org/api/where/stops.json")!
        let response = HTTPURLResponse(url: url, statusCode: 502, httpVersion: nil, headerFields: nil)!
        let error = APIError.requestFailure(response)
        let result = ErrorClassifier.classify(error, regionName: "Puget Sound")

        guard let apiError = result as? APIError else {
            fail("Expected APIError, got \(type(of: result))")
            return
        }

        switch apiError {
        case .serverUnavailable(let regionName, let statusCode):
            expect(regionName) == "Puget Sound"
            expect(statusCode) == 502
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

    func test_classify_requestFailure501_doesNotBecomeServerUnavailable() {
        let url = URL(string: "https://api.pugetsound.onebusaway.org/api/where/stops.json")!
        let response = HTTPURLResponse(url: url, statusCode: 501, httpVersion: nil, headerFields: nil)!
        let error = APIError.requestFailure(response)
        let result = ErrorClassifier.classify(error, regionName: "Puget Sound")

        guard let apiError = result as? APIError else {
            fail("Expected APIError, got \(type(of: result))")
            return
        }

        switch apiError {
        case .requestFailure(let resp):
            expect(resp.statusCode) == 501
        default:
            fail("Expected .requestFailure for 501, got \(apiError)")
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

    func test_classify_requestFailure503_withoutRegionName_staysAsRequestFailure() {
        let url = URL(string: "https://api.pugetsound.onebusaway.org/api/where/stops.json")!
        let response = HTTPURLResponse(url: url, statusCode: 503, httpVersion: nil, headerFields: nil)!
        let error = APIError.requestFailure(response)
        let result = ErrorClassifier.classify(error, regionName: nil)

        guard let apiError = result as? APIError else {
            fail("Expected APIError, got \(type(of: result))")
            return
        }

        switch apiError {
        case .requestFailure(let resp):
            expect(resp.statusCode) == 503
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

        switch apiError {
        case .requestFailure(let resp):
            expect(resp.statusCode) == 400
        default:
            fail("Expected .requestFailure for 4xx, got \(apiError)")
        }
    }

    // MARK: - Cellular Data Restriction (Injectable)

    func test_classify_networkFailure_withCellularRestricted_becomesCellularDataRestricted() {
        let error = APIError.networkFailure(nil)
        let result = ErrorClassifier.classify(error, regionName: "Puget Sound", isCellularDataRestricted: true)

        guard let apiError = result as? APIError else {
            fail("Expected APIError, got \(type(of: result))")
            return
        }

        switch apiError {
        case .cellularDataRestricted:
            break
        default:
            fail("Expected .cellularDataRestricted, got \(apiError)")
        }
    }

    func test_classify_networkFailure_withoutCellularRestricted_staysAsNetworkFailure() {
        let error = APIError.networkFailure(nil)
        let result = ErrorClassifier.classify(error, regionName: "Puget Sound", isCellularDataRestricted: false)

        guard let apiError = result as? APIError else {
            fail("Expected APIError, got \(type(of: result))")
            return
        }

        switch apiError {
        case .networkFailure:
            break
        default:
            fail("Expected .networkFailure, got \(apiError)")
        }
    }

    func test_classify_urlErrorNotConnected_withCellularRestricted_becomesCellularDataRestricted() {
        let urlError = NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet, userInfo: nil)
        let result = ErrorClassifier.classify(urlError, regionName: "Puget Sound", isCellularDataRestricted: true)

        guard let apiError = result as? APIError else {
            fail("Expected APIError, got \(type(of: result))")
            return
        }

        switch apiError {
        case .cellularDataRestricted:
            break
        default:
            fail("Expected .cellularDataRestricted, got \(apiError)")
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

    func test_classify_urlErrorCannotFindHost_withRegionName_becomesServerUnavailable() {
        let urlError = NSError(domain: NSURLErrorDomain, code: NSURLErrorCannotFindHost, userInfo: nil)
        let result = ErrorClassifier.classify(urlError, regionName: "San Diego")

        guard let apiError = result as? APIError else {
            fail("Expected APIError, got \(type(of: result))")
            return
        }

        switch apiError {
        case .serverUnavailable(let regionName, _):
            expect(regionName) == "San Diego"
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
            break
        default:
            fail("Expected .networkFailure when regionName is nil, got \(apiError)")
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
            break
        default:
            fail("Expected .networkFailure for unknown URL error, got \(apiError)")
        }
    }

    // MARK: - Idempotency (already-classified errors pass through unchanged)

    func test_classify_serverError_passesThrough() {
        let error = APIError.serverError(regionName: "Puget Sound")
        let result = ErrorClassifier.classify(error, regionName: "Tampa")

        guard let apiError = result as? APIError else {
            fail("Expected APIError, got \(type(of: result))")
            return
        }

        switch apiError {
        case .serverError(let regionName):
            expect(regionName) == "Puget Sound"
        default:
            fail("Expected .serverError to pass through, got \(apiError)")
        }
    }

    func test_classify_serverUnavailable_passesThrough() {
        let error = APIError.serverUnavailable(regionName: "Puget Sound", statusCode: 503)
        let result = ErrorClassifier.classify(error, regionName: "Tampa")

        guard let apiError = result as? APIError else {
            fail("Expected APIError, got \(type(of: result))")
            return
        }

        switch apiError {
        case .serverUnavailable(let regionName, let statusCode):
            expect(regionName) == "Puget Sound"
            expect(statusCode) == 503
        default:
            fail("Expected .serverUnavailable to pass through, got \(apiError)")
        }
    }

    func test_classify_cellularDataRestricted_passesThrough() {
        let error = APIError.cellularDataRestricted
        let result = ErrorClassifier.classify(error, regionName: "Puget Sound")

        guard let apiError = result as? APIError else {
            fail("Expected APIError, got \(type(of: result))")
            return
        }

        switch apiError {
        case .cellularDataRestricted:
            break
        default:
            fail("Expected .cellularDataRestricted to pass through, got \(apiError)")
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

    // MARK: - Error Description Verification

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
