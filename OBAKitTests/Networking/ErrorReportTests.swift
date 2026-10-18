//
//  ErrorReportTests.swift
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
final class ErrorReportTests {

    private let base = "https://api.pugetsound.onebusaway.org/api/where"

    private func response(_ path: String, status: Int) -> HTTPURLResponse {
        HTTPURLResponse(url: URL(string: "\(base)/\(path)?key=SECRET&app_uid=abc")!, statusCode: status, httpVersion: nil, headerFields: nil)!
    }

    private func report(_ error: Error, region: String? = "Puget Sound", cellularRestricted: Bool = false) -> ErrorReport {
        ErrorReport(
            error: error,
            regionName: region,
            isCellularDataRestricted: cellularRestricted,
            date: Date(timeIntervalSince1970: 1_792_280_292),
            appVersion: "25.4.1",
            systemVersion: "26.1",
            deviceModel: "iPhone16,1",
            reference: "7F3K-Q2"
        )
    }

    // MARK: - Subjects

    @Test func `Subject comes from the endpoint`() {
        let cases: [(String, ErrorReport.Subject)] = [
            ("arrivals-and-departures-for-stop/1_20170.json", .arrivalTimes),
            ("stop/1_20170.json", .arrivalTimes),
            ("trip-details/1_871781411.json", .livePosition),
            ("trip-for-vehicle/1_1234.json", .livePosition),
            ("schedule-for-stop/1_20170.json", .schedule),
            ("stops-for-location.json", .nearbyStops),
            ("stops-for-route/1_100275.json", .routeMap),
            ("shape/1_abc.json", .routeMap),
            ("search/stop.json", .searchResults),
            ("current-time.json", .unknown)
        ]
        for (path, expected) in cases {
            #expect(ErrorReport.Subject(url: URL(string: "\(base)/\(path)")) == expected, "\(path)")
        }
        #expect(ErrorReport.Subject(url: nil) == .unknown)
    }

    // MARK: - Causes

    /// The screenshot in #1582: a 429 used to read "The server encountered an
    /// error … status code 429" with the URL pasted in.
    @Test func `429 is rate limited with rider-facing copy`() {
        let report = report(APIError.requestFailure(response("trip-details/1_871781411.json", status: 429)))
        #expect(report.cause == .rateLimited)
        #expect(report.title == "Couldn't load live position")
        #expect(report.summary.hasSuffix("is busy."))
        #expect(report.errorCode == "429 Too Many Requests (rateLimited)")
        #expect(report.action == .details)
    }

    @Test func `404 on a trip means the trip ended`() {
        let report = report(APIError.requestNotFound(response("trip-details/1_1.json", status: 404)))
        #expect(report.cause == .tripNotFound)
        #expect(report.summary == "This trip has ended.")
    }

    @Test func `404 on a stop means it's not in service`() {
        let report = report(APIError.requestNotFound(response("arrivals-and-departures-for-stop/1_1.json", status: 404)))
        #expect(report.cause == .stopNotFound)
    }

    @Test func `500 names the region`() {
        let report = report(APIError.requestFailure(response("stops-for-location.json", status: 500)))
        #expect(report.cause == .serverError)
        #expect(report.title == "Couldn't load nearby stops")
        #expect(report.summary == "The Puget Sound server hit a problem.")
    }

    @Test func `Timeout is unreachable and keeps the failing URL`() {
        let url = URL(string: "\(base)/stops-for-route/1_100275.json?key=SECRET")!
        let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut, userInfo: [NSURLErrorFailingURLErrorKey: url])
        let report = report(error)
        #expect(report.cause == .serverUnavailable)
        #expect(report.title == "Couldn't load the route map")
        #expect(report.errorCode == "NSURLErrorDomain -1001 (serverUnavailable)")
    }

    /// With no region name the classifier leaves a timeout as a network
    /// failure. The phone is online, so it mustn't read "You're offline".
    @Test func `Timeout without a region is not offline`() {
        let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut)
        let report = report(error, region: nil)
        #expect(report.cause == .serverUnavailable)
        #expect(!report.cause.isRiderActionable)
    }

    @Test func `Decoding error names the case`() {
        let context = DecodingError.Context(codingPath: [], debugDescription: "missing")
        let report = report(DecodingError.keyNotFound(AnyKey("id"), context))
        #expect(report.cause == .invalidResponseData)
        #expect(report.errorCode == "DecodingError.keyNotFound")
    }

    @Test func `Unknown 418 uses the fallback`() {
        let report = report(APIError.requestFailure(response("arrivals-and-departures-for-stop/1_20170.json", status: 418)))
        #expect(report.cause == .fallback)
        #expect(report.title == "Couldn't load arrival times")
        #expect(report.summary == "Something went wrong.")
        #expect(report.errorCode == "418 (requestFailure)")
    }

    @Test func `Rider-side causes are flagged and cellular opens Settings`() {
        let offline = report(NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet))
        #expect(offline.cause == .offline)
        #expect(offline.cause.isRiderActionable)

        let cellular = report(NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet), cellularRestricted: true)
        #expect(cellular.cause == .cellularDataRestricted)
        #expect(cellular.action == .openSettings)

        #expect(report(APIError.captivePortal).cause == .captivePortal)
        #expect(!report(APIError.requestFailure(response("stop/1.json", status: 500))).cause.isRiderActionable)
    }

    @Test func `Survey not configured is silent`() {
        #expect(report(APIError.surveyServiceNotConfigured).isSilent)
    }

    // MARK: - Support details

    /// The API key travels in the query string; it must never reach a
    /// screenshot or a pasted report.
    @Test func `Request URL drops the query string`() {
        let report = report(APIError.requestFailure(response("trip-details/1_871781411.json", status: 429)))
        #expect(report.requestURL?.absoluteString == "\(base)/trip-details/1_871781411.json")
        #expect(report.displayRequest == "api.pugetsound.onebusaway.org/api/where/trip-details/1_871781411.json")
        #expect(!report.shareText.contains("SECRET"))
    }

    @Test func `Share text carries everything support needs`() {
        let text = report(APIError.requestFailure(response("trip-details/1_871781411.json", status: 429))).shareText
        #expect(text.contains("Couldn't load live position — "))
        #expect(text.contains("Error: 429 Too Many Requests (rateLimited)"))
        #expect(text.contains("Region: Puget Sound"))
        #expect(text.contains("Request: \(base)/trip-details/1_871781411.json"))
        #expect(text.contains("App: 25.4.1 · iOS 26.1 · iPhone16,1"))
        #expect(text.contains("Ref: 7F3K-Q2"))
    }

    @Test func `Reference is readable aloud`() {
        for _ in 0..<50 {
            let reference = ErrorReport.makeReference()
            #expect(reference.count == 7)
            #expect(reference.dropFirst(4).first == "-")
            #expect(reference.allSatisfy { !"01ILO".contains($0) })
        }
    }

    @Test func `Classifier maps 429 to rate limited`() {
        let classified = ErrorClassifier.classify(APIError.requestFailure(response("stop/1.json", status: 429)), regionName: nil)
        guard case .rateLimited = classified as? APIError else {
            Issue.record("Expected .rateLimited, got \(classified)")
            return
        }
    }

    /// An error that isn't about a request keeps its own message rather than
    /// becoming "Something went wrong".
    @Test func `Error with its own message keeps it`() {
        let report = report(UnstructuredError("This stop is in a different region."))
        #expect(report.cause == .message)
        #expect(report.summary == "This stop is in a different region.")
        #expect(report.explanation == "This stop is in a different region.")
    }

    /// Without a region the classifier turns these into an `UnstructuredError`;
    /// they must still read as unreadable data, under the endpoint's title.
    @Test func `Unreadable payload without a region isn't its own message`() {
        let context = DecodingError.Context(codingPath: [], debugDescription: "missing")
        let decoding = report(DecodingError.keyNotFound(AnyKey("id"), context), region: nil)
        #expect(decoding.cause == .invalidResponseData)

        let blank = report(APIError.requestNotFound(response("trip-details/1_1.json", status: 200)), region: nil)
        #expect(blank.cause == .invalidResponseData)
        #expect(blank.title == "Couldn't load live position")
    }

    @Test func `Cancelled requests are silent`() {
        #expect(report(NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled)).isSilent)
        #expect(report(APIError.networkFailure(NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled))).isSilent)
        #expect(report(CancellationError()).isSilent)
    }

    @Test func `NSError with an explicit description keeps it`() {
        let error = NSError(domain: "MKErrorDomain", code: 4, userInfo: [NSLocalizedDescriptionKey: "Directions Not Available"])
        let report = report(error)
        #expect(report.cause == .message)
        #expect(report.summary == "Directions Not Available")
    }

    @Test func `Stop prefix doesn't swallow other stop endpoints`() {
        #expect(ErrorReport.Subject(url: URL(string: "\(base)/stops-for-agency/1.json")) == .unknown)
    }
}

private struct AnyKey: CodingKey {
    let stringValue: String
    let intValue: Int? = nil
    init(_ value: String) { stringValue = value }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}
