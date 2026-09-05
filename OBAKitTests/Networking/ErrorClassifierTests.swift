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

    /// A literal 404 keeps `requestNotFound`'s own copy. Half of the boundary added
    /// in #1336 — the other half is the empty-200 reclassification below.
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

    @Test func `Classify request failure 500 becomes server error`() {
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

    @Test func `Classify request failure 502 becomes server unavailable`() {
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

    @Test func `Classify request failure 503 becomes server unavailable`() {
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

    @Test func `Classify request failure 501 does not become server unavailable`() {
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

    @Test func `Classify request failure 500 without region name stays as request failure`() {
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

    @Test func `Classify request failure 503 without region name stays as request failure`() {
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

    @Test func `Classify request failure 400 does not become server unavailable`() {
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

    // MARK: - Empty HTTP 200 Thrown As Request Not Found (#1336)

    /// `APIService+GetData` throws `requestNotFound` for a blank HTTP 200 as well as for
    /// a literal 404, and `requestNotFound`'s description is hardcoded to "404 Not found
    /// (url)". Riders must not be shown a status code the server never sent.
    @Test func `Classify request not found carrying a 200 becomes invalid response data`() {
        let url = URL(string: "https://api.pugetsound.onebusaway.org/api/where/arrivals-and-departures-for-stop/1_75403.json")!
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        let error = APIError.requestNotFound(response)
        let result = ErrorClassifier.classify(error, regionName: "Puget Sound")

        guard let apiError = result as? APIError else {
            Issue.record("Expected APIError, got \(type(of: result))")
            return
        }

        switch apiError {
        case .invalidResponseData(let regionName):
            #expect(regionName == "Puget Sound")
        default:
            Issue.record("Expected .invalidResponseData, got \(apiError)")
        }
    }

    /// `.invalidResponseData`'s copy names the region, so with no region the classifier
    /// falls back to the region-less wording. Handing the error back unchanged would
    /// re-emit the "404 Not found" copy this case exists to prevent.
    @Test func `Classify request not found carrying a 200 with no region uses neutral copy`() {
        let url = URL(string: "https://api.pugetsound.onebusaway.org/api/where/arrivals-and-departures-for-stop/1_75403.json")!
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        let error = APIError.requestNotFound(response)
        let result = ErrorClassifier.classify(error, regionName: nil)

        #expect(!(result is APIError))
        let description = result.localizedDescription
        #expect(!description.contains("404"))
        #expect(description.contains("can't read"))
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

    @Test func `Classify decoding error with region name becomes invalid response data`() {
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
        case .invalidResponseData(let regionName):
            #expect(regionName == "San Diego")
        case .serverUnavailable:
            Issue.record("DecodingError must not be classified as an unreachable server")
        default:
            Issue.record("Expected .invalidResponseData, got \(apiError)")
        }
    }

    @Test func `Classify decoding error without region name returns user friendly error`() {
        let decodingError = DecodingError.dataCorrupted(
            DecodingError.Context(codingPath: [], debugDescription: "The given data was not valid JSON.")
        )
        let result = ErrorClassifier.classify(decodingError, regionName: nil)

        let description = result.localizedDescription
        #expect(!description.contains("couldn't be read"))
        #expect(description.contains("feed"))
        #expect(!description.contains("experiencing problems"))
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

    @Test func `Classify invalid response data passes through`() {
        let error = APIError.invalidResponseData(regionName: "Puget Sound")
        let result = ErrorClassifier.classify(error, regionName: "Tampa")

        guard let apiError = result as? APIError else {
            Issue.record("Expected APIError, got \(type(of: result))")
            return
        }

        switch apiError {
        case .invalidResponseData(let regionName):
            #expect(regionName == "Puget Sound")
        default:
            Issue.record("Expected .invalidResponseData to pass through, got \(apiError)")
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
        #expect(description.contains("Unable to reach"))
        #expect(description.contains("VPN"))
        #expect(!description.contains("appears to be down right now"))
    }

    @Test func `Invalid response data error description does not claim the server is down`() {
        let error = APIError.invalidResponseData(regionName: "San Diego")
        let description = error.localizedDescription

        #expect(description.contains("San Diego"))
        #expect(description.contains("can't read"))
        #expect(!description.contains("down"))
        #expect(!description.contains("VPN"))
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
