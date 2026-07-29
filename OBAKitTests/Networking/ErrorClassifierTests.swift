//
//  ErrorClassifierTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
@testable import OBAKitCore

@MainActor
@Suite(.serialized)
final class ErrorClassifierTests {

    // MARK: - APIError Pass-Through

    @Test func `Classify captive portal passes through`() {
        let error = APIError.captivePortal
        let result = ErrorClassifier.classify(error, regionName: "Puget Sound")

        guard let apiError = result as? APIError else {
            Issue.record("Expected APIError, got \(type(of: result))")
            return
        }

        switch apiError {
        case .captivePortal:
            break
        default:
            Issue.record("Expected .captivePortal, got \(apiError)")
        }
    }

    @Test func `Classify request not found passes through`() {
        let url = URL(string: "https://api.pugetsound.onebusaway.org/api/where/stop/1_75403.json")!
        let response = HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!
        let error = APIError.requestNotFound(response)
        let result = ErrorClassifier.classify(error, regionName: "Puget Sound")

        guard let apiError = result as? APIError else {
            Issue.record("Expected APIError, got \(type(of: result))")
            return
        }

        switch apiError {
        case .requestNotFound:
            break
        default:
            Issue.record("Expected .requestNotFound, got \(apiError)")
        }
    }

    @Test func `Classify no response body passes through`() {
        let error = APIError.noResponseBody
        let result = ErrorClassifier.classify(error, regionName: "Puget Sound")

        guard let apiError = result as? APIError else {
            Issue.record("Expected APIError, got \(type(of: result))")
            return
        }

        switch apiError {
        case .noResponseBody:
            break
        default:
            Issue.record("Expected .noResponseBody, got \(apiError)")
        }
    }

    @Test func `Classify invalid content type passes through`() {
        let error = APIError.invalidContentType(
            originalError: nil,
            expectedContentType: "application/json",
            actualContentType: "text/html"
        )
        let result = ErrorClassifier.classify(error, regionName: "Puget Sound")

        guard let apiError = result as? APIError else {
            Issue.record("Expected APIError, got \(type(of: result))")
            return
        }

        switch apiError {
        case .invalidContentType:
            break
        default:
            Issue.record("Expected .invalidContentType, got \(apiError)")
        }
    }

    // MARK: - Server Error Classification (500 vs other 5xx)

    @Test func `Classify request failure500 becomes server error`() {
        let url = URL(string: "https://api.pugetsound.onebusaway.org/api/where/stops.json")!
        let response = HTTPURLResponse(url: url, statusCode: 500, httpVersion: nil, headerFields: nil)!
        let error = APIError.requestFailure(response)
        let result = ErrorClassifier.classify(error, regionName: "Puget Sound")

        guard let apiError = result as? APIError else {
            Issue.record("Expected APIError, got \(type(of: result))")
            return
        }

        switch apiError {
        case .serverError(let regionName):
            #expect(regionName == "Puget Sound")
        default:
            Issue.record("Expected .serverError, got \(apiError)")
        }
    }

    @Test func `Server error error description suggests retry`() {
        let error = APIError.serverError(regionName: "Puget Sound")
        let description = error.localizedDescription

        #expect(description.contains("Puget Sound"))
        #expect(description.contains("try again"))
    }

    @Test func `Classify request failure502 becomes server unavailable`() {
        let url = URL(string: "https://api.pugetsound.onebusaway.org/api/where/stops.json")!
        let response = HTTPURLResponse(url: url, statusCode: 502, httpVersion: nil, headerFields: nil)!
        let error = APIError.requestFailure(response)
        let result = ErrorClassifier.classify(error, regionName: "Puget Sound")

        guard let apiError = result as? APIError else {
            Issue.record("Expected APIError, got \(type(of: result))")
            return
        }

        switch apiError {
        case .serverUnavailable(let regionName, let statusCode):
            #expect(regionName == "Puget Sound")
            #expect(statusCode == 502)
        default:
            Issue.record("Expected .serverUnavailable, got \(apiError)")
        }
    }

    @Test func `Classify request failure503 becomes server unavailable`() {
        let url = URL(string: "https://api.pugetsound.onebusaway.org/api/where/stops.json")!
        let response = HTTPURLResponse(url: url, statusCode: 503, httpVersion: nil, headerFields: nil)!
        let error = APIError.requestFailure(response)
        let result = ErrorClassifier.classify(error, regionName: "Tampa")

        guard let apiError = result as? APIError else {
            Issue.record("Expected APIError, got \(type(of: result))")
            return
        }

        switch apiError {
        case .serverUnavailable(let regionName, let statusCode):
            #expect(regionName == "Tampa")
            #expect(statusCode == 503)
        default:
            Issue.record("Expected .serverUnavailable, got \(apiError)")
        }
    }

    @Test func `Classify request failure501 does not become server unavailable`() {
        let url = URL(string: "https://api.pugetsound.onebusaway.org/api/where/stops.json")!
        let response = HTTPURLResponse(url: url, statusCode: 501, httpVersion: nil, headerFields: nil)!
        let error = APIError.requestFailure(response)
        let result = ErrorClassifier.classify(error, regionName: "Puget Sound")

        guard let apiError = result as? APIError else {
            Issue.record("Expected APIError, got \(type(of: result))")
            return
        }

        switch apiError {
        case .requestFailure(let resp):
            #expect(resp.statusCode == 501)
        default:
            Issue.record("Expected .requestFailure for 501, got \(apiError)")
        }
    }

    @Test func `Classify request failure500 without region name stays as request failure`() {
        let url = URL(string: "https://api.pugetsound.onebusaway.org/api/where/stops.json")!
        let response = HTTPURLResponse(url: url, statusCode: 500, httpVersion: nil, headerFields: nil)!
        let error = APIError.requestFailure(response)
        let result = ErrorClassifier.classify(error, regionName: nil)

        guard let apiError = result as? APIError else {
            Issue.record("Expected APIError, got \(type(of: result))")
            return
        }

        switch apiError {
        case .requestFailure(let resp):
            #expect(resp.statusCode == 500)
        default:
            Issue.record("Expected .requestFailure to pass through when regionName is nil, got \(apiError)")
        }
    }

    @Test func `Classify request failure503 without region name stays as request failure`() {
        let url = URL(string: "https://api.pugetsound.onebusaway.org/api/where/stops.json")!
        let response = HTTPURLResponse(url: url, statusCode: 503, httpVersion: nil, headerFields: nil)!
        let error = APIError.requestFailure(response)
        let result = ErrorClassifier.classify(error, regionName: nil)

        guard let apiError = result as? APIError else {
            Issue.record("Expected APIError, got \(type(of: result))")
            return
        }

        switch apiError {
        case .requestFailure(let resp):
            #expect(resp.statusCode == 503)
        default:
            Issue.record("Expected .requestFailure to pass through when regionName is nil, got \(apiError)")
        }
    }

    @Test func `Classify request failure400 does not become server unavailable`() {
        let url = URL(string: "https://api.pugetsound.onebusaway.org/api/where/stops.json")!
        let response = HTTPURLResponse(url: url, statusCode: 400, httpVersion: nil, headerFields: nil)!
        let error = APIError.requestFailure(response)
        let result = ErrorClassifier.classify(error, regionName: "Puget Sound")

        guard let apiError = result as? APIError else {
            Issue.record("Expected APIError, got \(type(of: result))")
            return
        }

        switch apiError {
        case .requestFailure(let resp):
            #expect(resp.statusCode == 400)
        default:
            Issue.record("Expected .requestFailure for 4xx, got \(apiError)")
        }
    }

    // MARK: - Cellular Data Restriction (Injectable)

    @Test func `Classify network failure with cellular restricted becomes cellular data restricted`() {
        let error = APIError.networkFailure(nil)
        let result = ErrorClassifier.classify(error, regionName: "Puget Sound", isCellularDataRestricted: true)

        guard let apiError = result as? APIError else {
            Issue.record("Expected APIError, got \(type(of: result))")
            return
        }

        switch apiError {
        case .cellularDataRestricted:
            break
        default:
            Issue.record("Expected .cellularDataRestricted, got \(apiError)")
        }
    }

    @Test func `Classify network failure without cellular restricted stays as network failure`() {
        let error = APIError.networkFailure(nil)
        let result = ErrorClassifier.classify(error, regionName: "Puget Sound", isCellularDataRestricted: false)

        guard let apiError = result as? APIError else {
            Issue.record("Expected APIError, got \(type(of: result))")
            return
        }

        switch apiError {
        case .networkFailure:
            break
        default:
            Issue.record("Expected .networkFailure, got \(apiError)")
        }
    }

    @Test func `Classify url error not connected with cellular restricted becomes cellular data restricted`() {
        let urlError = NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet, userInfo: nil)
        let result = ErrorClassifier.classify(urlError, regionName: "Puget Sound", isCellularDataRestricted: true)

        guard let apiError = result as? APIError else {
            Issue.record("Expected APIError, got \(type(of: result))")
            return
        }

        switch apiError {
        case .cellularDataRestricted:
            break
        default:
            Issue.record("Expected .cellularDataRestricted, got \(apiError)")
        }
    }

    // MARK: - DecodingError Classification

    @Test func `Classify decoding error with region name becomes server unavailable`() {
        let decodingError = DecodingError.keyNotFound(
            AnyCodingKey(stringValue: "data")!,
            DecodingError.Context(codingPath: [], debugDescription: "No value associated with key")
        )
        let result = ErrorClassifier.classify(decodingError, regionName: "San Diego")

        guard let apiError = result as? APIError else {
            Issue.record("Expected APIError, got \(type(of: result))")
            return
        }

        switch apiError {
        case .serverUnavailable(let regionName, let statusCode):
            #expect(regionName == "San Diego")
            #expect(statusCode == nil)
        default:
            Issue.record("Expected .serverUnavailable, got \(apiError)")
        }
    }

    @Test func `Classify decoding error without region name returns user friendly error`() {
        let decodingError = DecodingError.dataCorrupted(
            DecodingError.Context(codingPath: [], debugDescription: "The given data was not valid JSON.")
        )
        let result = ErrorClassifier.classify(decodingError, regionName: nil)

        let description = result.localizedDescription
        #expect(!description.contains("couldn't be read"))
        #expect(description.contains("server"))
    }

    // MARK: - NSURLError Classification

    @Test func `Classify url error timed out with region name becomes server unavailable`() {
        let urlError = NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut, userInfo: nil)
        let result = ErrorClassifier.classify(urlError, regionName: "York Region")

        guard let apiError = result as? APIError else {
            Issue.record("Expected APIError, got \(type(of: result))")
            return
        }

        switch apiError {
        case .serverUnavailable(let regionName, _):
            #expect(regionName == "York Region")
        default:
            Issue.record("Expected .serverUnavailable for timeout, got \(apiError)")
        }
    }

    @Test func `Classify url error cannot connect to host with region name becomes server unavailable`() {
        let urlError = NSError(domain: NSURLErrorDomain, code: NSURLErrorCannotConnectToHost, userInfo: nil)
        let result = ErrorClassifier.classify(urlError, regionName: "Tampa")

        guard let apiError = result as? APIError else {
            Issue.record("Expected APIError, got \(type(of: result))")
            return
        }

        switch apiError {
        case .serverUnavailable(let regionName, _):
            #expect(regionName == "Tampa")
        default:
            Issue.record("Expected .serverUnavailable, got \(apiError)")
        }
    }

    @Test func `Classify url error cannot find host with region name becomes server unavailable`() {
        let urlError = NSError(domain: NSURLErrorDomain, code: NSURLErrorCannotFindHost, userInfo: nil)
        let result = ErrorClassifier.classify(urlError, regionName: "San Diego")

        guard let apiError = result as? APIError else {
            Issue.record("Expected APIError, got \(type(of: result))")
            return
        }

        switch apiError {
        case .serverUnavailable(let regionName, _):
            #expect(regionName == "San Diego")
        default:
            Issue.record("Expected .serverUnavailable, got \(apiError)")
        }
    }

    @Test func `Classify url error timed out without region name becomes network failure`() {
        let urlError = NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut, userInfo: nil)
        let result = ErrorClassifier.classify(urlError, regionName: nil)

        guard let apiError = result as? APIError else {
            Issue.record("Expected APIError, got \(type(of: result))")
            return
        }

        switch apiError {
        case .networkFailure:
            break
        default:
            Issue.record("Expected .networkFailure when regionName is nil, got \(apiError)")
        }
    }

    @Test func `Classify url error unknown code becomes network failure`() {
        let urlError = NSError(domain: NSURLErrorDomain, code: NSURLErrorUnknown, userInfo: nil)
        let result = ErrorClassifier.classify(urlError, regionName: "Puget Sound")

        guard let apiError = result as? APIError else {
            Issue.record("Expected APIError, got \(type(of: result))")
            return
        }

        switch apiError {
        case .networkFailure:
            break
        default:
            Issue.record("Expected .networkFailure for unknown URL error, got \(apiError)")
        }
    }

    // MARK: - Idempotency (already-classified errors pass through unchanged)

    @Test func `Classify server error passes through`() {
        let error = APIError.serverError(regionName: "Puget Sound")
        let result = ErrorClassifier.classify(error, regionName: "Tampa")

        guard let apiError = result as? APIError else {
            Issue.record("Expected APIError, got \(type(of: result))")
            return
        }

        switch apiError {
        case .serverError(let regionName):
            #expect(regionName == "Puget Sound")
        default:
            Issue.record("Expected .serverError to pass through, got \(apiError)")
        }
    }

    @Test func `Classify server unavailable passes through`() {
        let error = APIError.serverUnavailable(regionName: "Puget Sound", statusCode: 503)
        let result = ErrorClassifier.classify(error, regionName: "Tampa")

        guard let apiError = result as? APIError else {
            Issue.record("Expected APIError, got \(type(of: result))")
            return
        }

        switch apiError {
        case .serverUnavailable(let regionName, let statusCode):
            #expect(regionName == "Puget Sound")
            #expect(statusCode == 503)
        default:
            Issue.record("Expected .serverUnavailable to pass through, got \(apiError)")
        }
    }

    @Test func `Classify cellular data restricted passes through`() {
        let error = APIError.cellularDataRestricted
        let result = ErrorClassifier.classify(error, regionName: "Puget Sound")

        guard let apiError = result as? APIError else {
            Issue.record("Expected APIError, got \(type(of: result))")
            return
        }

        switch apiError {
        case .cellularDataRestricted:
            break
        default:
            Issue.record("Expected .cellularDataRestricted to pass through, got \(apiError)")
        }
    }

    // MARK: - Non-Network Errors Pass Through

    @Test func `Classify arbitrary error passes through`() {
        let error = NSError(domain: "com.example.test", code: 42, userInfo: [
            NSLocalizedDescriptionKey: "Something unrelated happened"
        ])
        let result = ErrorClassifier.classify(error, regionName: "Puget Sound")

        #expect(result.localizedDescription == "Something unrelated happened")
    }

    // MARK: - Error Description Verification

    @Test func `Server unavailable error description contains region name`() {
        let error = APIError.serverUnavailable(regionName: "Puget Sound", statusCode: 502)
        let description = error.localizedDescription

        #expect(description.contains("Puget Sound"))
        #expect(description.contains("down"))
    }

    @Test func `Cellular data restricted error description mentions settings`() {
        let error = APIError.cellularDataRestricted
        let description = error.localizedDescription

        #expect(description.contains("Settings"))
        #expect(description.contains("Cellular"))
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
