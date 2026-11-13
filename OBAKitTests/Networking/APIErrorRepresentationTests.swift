//
//  APIErrorRepresentationTests.swift
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
final class APIErrorRepresentationTests {

    private func makeHTTPResponse(statusCode: Int, url: URL = URL(string: "https://example.com/api/test")!, contentType: String? = nil) -> HTTPURLResponse {
        var headerFields: [String: String] = [:]
        if let contentType {
            headerFields["Content-Type"] = contentType
        }
        return HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: "2.0", headerFields: headerFields)!
    }

    // MARK: - meansOnDemandUnsupported Heuristic

    @Test func `meansOnDemandUnsupported true for requestNotFound`() {
        let response404 = makeHTTPResponse(statusCode: 404)
        let error404 = APIError.requestNotFound(response404)
        #expect(error404.meansOnDemandUnsupported)

        let response200Blank = makeHTTPResponse(statusCode: 200)
        let errorBlank = APIError.requestNotFound(response200Blank)
        #expect(errorBlank.meansOnDemandUnsupported)
    }

    @Test func `meansOnDemandUnsupported true for HTML invalidContentType`() {
        let htmlError1 = APIError.invalidContentType(originalError: nil, expectedContentType: "json", actualContentType: "text/html")
        let htmlError2 = APIError.invalidContentType(originalError: nil, expectedContentType: "json", actualContentType: "text/html; charset=UTF-8")

        #expect(htmlError1.meansOnDemandUnsupported)
        #expect(htmlError2.meansOnDemandUnsupported)
    }

    @Test func `meansOnDemandUnsupported false for other errors`() {
        let jsonMismatch = APIError.invalidContentType(originalError: nil, expectedContentType: "json", actualContentType: "application/xml")
        let nilContent = APIError.invalidContentType(originalError: nil, expectedContentType: "json", actualContentType: nil)
        let network = APIError.networkFailure(nil)
        let captive = APIError.captivePortal
        let noBody = APIError.noResponseBody
        let server500 = APIError.requestFailure(makeHTTPResponse(statusCode: 500))

        #expect(!jsonMismatch.meansOnDemandUnsupported)
        #expect(!nilContent.meansOnDemandUnsupported)
        #expect(!network.meansOnDemandUnsupported)
        #expect(!captive.meansOnDemandUnsupported)
        #expect(!noBody.meansOnDemandUnsupported)
        #expect(!server500.meansOnDemandUnsupported)
    }

    // MARK: - errorDescription

    @Test func `Captive portal error description`() {
        let error = APIError.captivePortal
        let description = error.errorDescription
        #expect(description?.isEmpty == false)
    }

    @Test func `Invalid content type error description format`() {
        let error = APIError.invalidContentType(originalError: nil, expectedContentType: "application/json", actualContentType: "text/plain")
        let description = error.errorDescription
        #expect(description?.contains("application/json") == true)
        #expect(description?.contains("text/plain") == true)
    }

    @Test func `Invalid content type error description when actual is nil`() {
        let error = APIError.invalidContentType(originalError: nil, expectedContentType: "application/json", actualContentType: nil)
        let description = error.errorDescription
        #expect(description?.contains("application/json") == true)
        #expect(description?.contains("(nil)") == true)
    }

    @Test func `Network failure with failing URL includes host`() {
        let failingURL = URL(string: "https://api.pugetsound.onebusaway.org/api/where")!
        let underlying = NSError(
            domain: NSURLErrorDomain,
            code: NSURLErrorCannotConnectToHost,
            userInfo: [
                NSLocalizedDescriptionKey: "Could not connect to server.",
                NSURLErrorFailingURLErrorKey: failingURL
            ]
        )

        let error = APIError.networkFailure(underlying)
        let description = error.errorDescription
        #expect(description?.contains("api.pugetsound.onebusaway.org") == true)
    }

    @Test func `Network failure without underlying error provides fallback message`() {
        let error = APIError.networkFailure(nil)
        let description = error.errorDescription
        #expect(description?.isEmpty == false)
    }

    @Test func `Request failure description strips query params`() {
        let urlWithQuery = URL(string: "https://api.example.com/api/where/stops.json?key=TEST&lat=47.6")!
        let response500 = makeHTTPResponse(statusCode: 500, url: urlWithQuery)
        let error = APIError.requestFailure(response500)

        let description = error.errorDescription
        #expect(description?.contains("500") == true)
        #expect(description?.contains("https://api.example.com/api/where/stops.json") == true)
        #expect(description?.contains("key=TEST") == false)
    }

    @Test func `Request not found description includes full URL`() {
        let url = URL(string: "https://api.example.com/api/where/stop/missing.json")!
        let response404 = makeHTTPResponse(statusCode: 404, url: url)
        let error = APIError.requestNotFound(response404)

        let description = error.errorDescription
        #expect(description?.contains("404") == true)
        #expect(description?.contains(url.absoluteString) == true)
    }

    @Test func `Request not found description strips query params`() {
        let urlWithQuery = URL(string: "https://api.example.com/api/where/stop/1_1.json?key=TEST&lat=47.6")!
        let error = APIError.requestNotFound(makeHTTPResponse(statusCode: 404, url: urlWithQuery))

        let description = error.errorDescription
        #expect(description?.contains("https://api.example.com/api/where/stop/1_1.json") == true)
        #expect(description?.contains("key=TEST") == false)
        #expect(description?.contains("lat=47.6") == false)
    }

    // MARK: - Logged URLs (#1723)

    @Test func `Logged request URL drops the query`() {
        let request = URLRequest(url: URL(string: "https://api.example.com/api/where/stops-for-location.json?key=TEST&lat=47.6&lon=-122.3")!)
        #expect(request.loggableURL == "https://api.example.com/api/where/stops-for-location.json")
    }

    @Test func `Logged request URL without a query is unchanged`() {
        let request = URLRequest(url: URL(string: "https://api.example.com/api/where/config.json")!)
        #expect(request.loggableURL == "https://api.example.com/api/where/config.json")
    }

    @Test func `Logged network error description drops the failing URL's query`() {
        let failingURL = URL(string: "https://api.example.com/api/where/stops-for-location.json?key=TEST&lat=47.6")!
        let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut, userInfo: [
            NSURLErrorFailingURLErrorKey: failingURL,
            NSURLErrorFailingURLStringErrorKey: failingURL.absoluteString
        ])
        #expect(error.description.contains("key=TEST"), "Precondition: NSError's description includes the failing URL")

        let logged = (ErrorReport.sanitizedForReporting(error) as NSError).description
        #expect(logged.contains("stops-for-location.json"))
        #expect(!logged.contains("key=TEST"))
        #expect(!logged.contains("lat=47.6"))
    }

    @Test func `Regional errors contain region name`() {
        let region = "Puget Sound"

        let serverErr = APIError.serverError(regionName: region)
        #expect(serverErr.errorDescription?.contains(region) == true)

        let serverUnavail = APIError.serverUnavailable(regionName: region, statusCode: 503)
        #expect(serverUnavail.errorDescription?.contains(region) == true)

        let invalidData = APIError.invalidResponseData(regionName: region)
        #expect(invalidData.errorDescription?.contains(region) == true)
    }

    @Test func `Rate limited, survey not configured, and no region selected descriptions`() {
        let rateLimited = APIError.rateLimited
        #expect(rateLimited.errorDescription?.isEmpty == false)

        let surveyNotConfigured = APIError.surveyServiceNotConfigured
        #expect(surveyNotConfigured.errorDescription?.isEmpty == false)

        let noRegion = APIError.noRegionSelected
        #expect(noRegion.errorDescription?.isEmpty == false)
    }
}
