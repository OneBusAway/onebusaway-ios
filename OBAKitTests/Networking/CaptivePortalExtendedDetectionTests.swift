//
//  CaptivePortalExtendedDetectionTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import CFNetwork
import Testing
@testable import OBAKit
@testable import OBAKitCore

@Suite(.serialized)
final class CaptivePortalExtendedDetectionTests: OBATestCase {

    // MARK: - HTML Redirect Parsing Signatures

    @Test func `Cocoa error 3840 with custom user info userInfo matches captive portal`() {
        let service = buildRESTService()
        let userInfo: [String: Any] = [
            NSDebugDescriptionErrorKey: "JSON text did not start with array or object and option to allow fragments not set. around line 1, column 0.",
            "kCFErrorStringKey": "<html><head><title>WiFi Login</title></head></html>"
        ]
        let error = NSError(domain: NSCocoaErrorDomain, code: 3840, userInfo: userInfo)

        #expect(service.errorLooksLikeCaptivePortal(error))
    }

    // MARK: - CFNetwork Secure Connection Constraints

    @Test func `CFNetwork domain without ATS secure requirement does not indicate captive portal`() {
        let service = buildRESTService()
        let error = NSError(
            domain: "kCFErrorDomainCFNetwork",
            code: NSURLErrorCannotConnectToHost
        )

        #expect(!service.errorLooksLikeCaptivePortal(error))
    }

    // MARK: - Standard HTTP Status Segregation

    @Test func `Standard network errors like not connected to internet are not classified as captive portal`() {
        let service = buildRESTService()
        let errors = [
            NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet),
            NSError(domain: NSURLErrorDomain, code: NSURLErrorNetworkConnectionLost),
            NSError(domain: NSURLErrorDomain, code: NSURLErrorDNSLookupFailed),
            NSError(domain: NSURLErrorDomain, code: NSURLErrorCannotFindHost)
        ]

        for err in errors {
            #expect(!service.errorLooksLikeCaptivePortal(err))
        }
    }

    // MARK: - Arbitrary Domain Segregation

    @Test func `Unrelated domain with code 3840 is not misidentified as captive portal`() {
        let service = buildRESTService()
        let unrelatedError = NSError(domain: "com.onebusaway.unrelated", code: 3840)

        #expect(!service.errorLooksLikeCaptivePortal(unrelatedError))
    }
}
