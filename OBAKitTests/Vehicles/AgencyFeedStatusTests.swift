//
//  AgencyFeedStatusTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
@testable import OBAKit

@Suite(.serialized)
struct AgencyFeedStatusTests {

    // MARK: - Initialization & Defaults

    @Test func `Default initialization values are configured properly`() {
        let status = AgencyFeedStatus(id: "1", agencyName: "Metro Transit")

        #expect(status.id == "1")
        #expect(status.agencyName == "Metro Transit")
        #expect(status.lastFetchedAt == nil)
        #expect(status.vehicleCount == 0)
        #expect(status.error == nil)
        #expect(status.httpStatusCode == nil)
        #expect(status.dataSize == nil)
        #expect(!status.isSkipped)
        #expect(!status.isSuccess)
        #expect(status.statusDescription == "0 vehicles")
    }

    // MARK: - Success Determination

    @Test func `isSuccess is true only when error is nil and vehicleCount is greater than zero`() {
        var status = AgencyFeedStatus(id: "1", agencyName: "Metro Transit")

        // 0 vehicles, no error -> not success
        status.vehicleCount = 0
        status.error = nil
        #expect(!status.isSuccess)

        // > 0 vehicles, no error -> success
        status.vehicleCount = 42
        status.error = nil
        #expect(status.isSuccess)
        #expect(status.statusDescription == "42 vehicles")

        // > 0 vehicles, but has error -> not success
        status.error = .invalidURL
        #expect(!status.isSuccess)
        #expect(status.statusDescription == "The feed address is invalid.")
    }

    // MARK: - FeedError User-Friendly Descriptions

    @Test func `FeedError invalidURL description`() {
        let error = AgencyFeedStatus.FeedError.invalidURL
        #expect(error.userFriendlyDescription == "The feed address is invalid.")
    }

    @Test func `FeedError decodingError description`() {
        let nsError = NSError(domain: "test", code: -1)
        let error = AgencyFeedStatus.FeedError.decodingError(nsError)
        #expect(error.userFriendlyDescription == "The feed data couldn't be read. It may be in an unexpected format.")
    }

    @Test func `FeedError networkError descriptions for internet disconnected, timeout, and generic`() {
        let noInternetError = NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)
        let disconnected = AgencyFeedStatus.FeedError.networkError(noInternetError)
        #expect(disconnected.userFriendlyDescription == "No internet connection. Check your network settings.")

        let timeoutError = NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut)
        let timedOut = AgencyFeedStatus.FeedError.networkError(timeoutError)
        #expect(timedOut.userFriendlyDescription == "The request timed out. The server may be busy.")

        let genericError = NSError(domain: NSURLErrorDomain, code: NSURLErrorCannotFindHost)
        let generic = AgencyFeedStatus.FeedError.networkError(genericError)
        #expect(generic.userFriendlyDescription == "Unable to connect to the server. Please try again later.")
    }

    @Test func `FeedError httpError descriptions for 404, 5xx server error, and default codes`() {
        let notFound = AgencyFeedStatus.FeedError.httpError(404)
        #expect(notFound.userFriendlyDescription == "This agency doesn't provide a vehicle feed.")

        // Boundary tests for the 500...599 HTTP server error range
        let serverError499 = AgencyFeedStatus.FeedError.httpError(499)
        #expect(serverError499.userFriendlyDescription == "Server returned an error (code 499).")

        let serverError500 = AgencyFeedStatus.FeedError.httpError(500)
        #expect(serverError500.userFriendlyDescription == "The server is having problems. Please try again later.")

        let serverError503 = AgencyFeedStatus.FeedError.httpError(503)
        #expect(serverError503.userFriendlyDescription == "The server is having problems. Please try again later.")

        let serverError599 = AgencyFeedStatus.FeedError.httpError(599)
        #expect(serverError599.userFriendlyDescription == "The server is having problems. Please try again later.")

        let serverError600 = AgencyFeedStatus.FeedError.httpError(600)
        #expect(serverError600.userFriendlyDescription == "Server returned an error (code 600).")

        let unauthorized = AgencyFeedStatus.FeedError.httpError(401)
        #expect(unauthorized.userFriendlyDescription == "Server returned an error (code 401).")

        let forbidden = AgencyFeedStatus.FeedError.httpError(403)
        #expect(forbidden.userFriendlyDescription == "Server returned an error (code 403).")
    }

    // MARK: - Status Description

    @Test func `Status description displays error description when error is present`() {
        var status = AgencyFeedStatus(id: "40", agencyName: "Sound Transit")
        status.vehicleCount = 10
        status.error = .httpError(404)

        #expect(status.statusDescription == "This agency doesn't provide a vehicle feed.")
    }

    @Test func `Status description displays vehicle count when error is nil`() {
        var status = AgencyFeedStatus(id: "40", agencyName: "Sound Transit")
        status.vehicleCount = 125
        status.error = nil

        #expect(status.statusDescription == "125 vehicles")
    }
}
