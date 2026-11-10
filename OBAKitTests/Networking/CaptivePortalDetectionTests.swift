//
//  CaptivePortalDetectionTests.swift
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
final class CaptivePortalDetectionTests: OBATestCase {

    @Test func `CFNetwork ATS error looks like a captive portal`() {
        let service = buildRESTService()
        // Built from the real constant, so this fails if the literal in
        // production code ever stops matching CFNetwork's actual domain.
        let error = NSError(
            domain: kCFErrorDomainCFNetwork as String,
            code: NSURLErrorAppTransportSecurityRequiresSecureConnection
        )
        #expect(service.errorLooksLikeCaptivePortal(error))
    }

    @Test func `JSON parse failure looks like a captive portal`() {
        let service = buildRESTService()
        #expect(service.errorLooksLikeCaptivePortal(NSError(domain: NSCocoaErrorDomain, code: 3840)))
    }

    @Test func `Unrelated domain with code 3840 is not misidentified as captive portal`() {
        let service = buildRESTService()
        let unrelatedError = NSError(domain: "com.onebusaway.unrelated", code: 3840)
        #expect(!service.errorLooksLikeCaptivePortal(unrelatedError))
    }

    @Test func `Standard network errors are not classified as captive portal`() {
        let service = buildRESTService()
        let errors = [
            NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut),
            NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet),
            NSError(domain: NSURLErrorDomain, code: NSURLErrorNetworkConnectionLost),
            NSError(domain: NSURLErrorDomain, code: NSURLErrorDNSLookupFailed),
            NSError(domain: NSURLErrorDomain, code: NSURLErrorCannotFindHost)
        ]

        for err in errors {
            #expect(!service.errorLooksLikeCaptivePortal(err))
        }
    }
}
