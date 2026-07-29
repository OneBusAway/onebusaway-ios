//
//  RegionsEncodingTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import XCTest
import CoreLocation
import MapKit
import Testing
@testable import OBAKit
@testable import OBAKitCore

// swiftlint:disable function_body_length force_try

class RegionsEncodingTests: OBATestCase {

    func testRoundtrippingRegion() {
        let regionsObjects = try! Fixtures.loadRESTAPIPayload(type: [Region].self, fileName: "regions-v3.json")

        #expect(regionsObjects.count == 17)

        let tampa = regionsObjects[0]
        #expect(tampa.name == "Tampa Bay")
        #expect(tampa.isCustom == false)

        let plistData = try! PropertyListEncoder().encode(regionsObjects)
        let roundTripped = try! PropertyListDecoder().decode([Region].self, from: plistData)
        let tampaRT = roundTripped[0]

        #expect(roundTripped.count == 17)

        #expect(tampaRT.regionIdentifier == 0)
        #expect(tampaRT.name == "Tampa Bay")

        #expect(tampaRT.versionInfo == "2.4.15-cs|2|4|15|cs|d41e1a8978da14e98a2e19d109a23018957db7cf")
        #expect(tampaRT.language == "en_US")

        #expect(!tampaRT.supportsEmbeddedSocial)
        #expect(tampaRT.supportsOBADiscoveryAPIs)
        #expect(tampaRT.supportsOTPBikeshare)
        #expect(tampaRT.supportsSiriRealtimeAPIs)
        #expect(tampaRT.isActive)
        #expect(!tampaRT.isExperimental)
        #expect(tampaRT.isCustom == false)

        #expect(tampaRT.facebookURL == nil)
        #expect(tampaRT.contactEmail == "onebusaway@gohart.org")
        #expect(tampaRT.openTripPlannerContactEmail == "otp-tampa@onebusaway.org")
        #expect(tampaRT.twitterURL == URL(string: "https://mobile.twitter.com/OBA_tampa")!)

        #expect(tampaRT.OBABaseURL == URL(string: "https://api.tampa.onebusaway.org/api/")!)
        #expect(tampa.sidecarBaseURL == URL(string: "https://onebusaway.co")!)
        #expect(tampaRT.siriBaseURL == URL(string: "https://tampa.onebusaway.org/onebusaway-api-webapp/siri/")!)
        #expect(tampaRT.openTripPlannerURL == URL(string: "https://otp.prod.obahart.org/otp/")!)
        #expect(tampaRT.stopInfoURL == nil)

        #expect(tampaRT.paymentWarningBody == nil)
        #expect(tampaRT.paymentWarningTitle == nil)
        #expect(tampaRT.paymentAndroidAppID == "co.bytemark.flamingo")
        #expect(tampaRT.paymentiOSAppStoreIdentifier == "1487465395")
        #expect(tampaRT.paymentiOSAppURLScheme == "fb313213768708402HART")

        let open311 = tampaRT.open311Servers!.first!
        #expect(open311.jurisdictionID == nil)
        #expect(open311.apiKey == "937033cad3054ec58a1a8156dcdd6ad8a416af2f")
        #expect(open311.baseURL == URL(string: "https://seeclickfix.com/open311/v2/")!)

        let bounds = tampaRT.regionBounds
        expectClose(bounds[0].lat, 27.976910500000002)
        expectClose(bounds[0].lon, -82.445851)
        expectClose(bounds[0].latSpan, 0.5424609999999994)
        expectClose(bounds[0].lonSpan, 0.576357999999999)

        expectClose(bounds[1].lat, 27.919249999999998)
        expectClose(bounds[1].lon, -82.652145)
        expectClose(bounds[1].latSpan, 0.47208000000000183)
        expectClose(bounds[1].lonSpan, 0.3967700000000036)
    }

    func testUmamiAnalyticsDecoding() {
        let regions = try! Fixtures.loadRESTAPIPayload(type: [Region].self, fileName: "regions-v3.json")

        // Present: region 0 decodes url + id.
        let umami = regions[0].umamiAnalytics
        #expect(umami?.url == URL(string: "https://analytics.onebusawaycloud.com")!)
        #expect(umami?.id == "abc-123-uuid")

        // Explicit JSON null (region 1) → nil.
        #expect(regions[1].umamiAnalytics == nil)

        // Absent key (region 2) → nil.
        #expect(regions[2].umamiAnalytics == nil)

        // Survives a property-list encode → decode round trip (Region is persisted to disk).
        let plist = try! PropertyListEncoder().encode(regions)
        let roundTripped = try! PropertyListDecoder().decode([Region].self, from: plist)
        #expect(roundTripped[0].umamiAnalytics?.url == URL(string: "https://analytics.onebusawaycloud.com")!)
        #expect(roundTripped[0].umamiAnalytics?.id == "abc-123-uuid")
        #expect(roundTripped[1].umamiAnalytics == nil)
    }

    func testCustomRegions_creation() {
        let customRegion = Fixtures.customMinneapolisRegion

        #expect(customRegion.name == "Custom Region")
        #expect(customRegion.OBABaseURL.absoluteString == "http://www.example.com")
        #expect(customRegion.contactEmail == "contact@example.com")

        expectClose(customRegion.serviceRect.origin.coordinate.latitude, 44.9778, within: 0.1)
        expectClose(customRegion.serviceRect.origin.coordinate.longitude, -93.2650, within: 0.1)
        expectClose(customRegion.serviceRect.height, 9485.2270, within: 0.1)
        expectClose(customRegion.serviceRect.width, 9453.3477, within: 0.1)
    }

    func testCustomRegions_roundtripping() {
        let customRegion = Fixtures.customMinneapolisRegion
        let plistData = try! PropertyListEncoder().encode([customRegion])
        let roundTripped = try! PropertyListDecoder().decode([Region].self, from: plistData)
        let customRegionRT = roundTripped[0]

        #expect(customRegionRT.name == "Custom Region")
        #expect(customRegionRT.OBABaseURL.absoluteString == "http://www.example.com")
        #expect(customRegionRT.contactEmail == "contact@example.com")

        expectClose(customRegionRT.serviceRect.origin.coordinate.latitude, 44.9778, within: 0.1)
        expectClose(customRegionRT.serviceRect.origin.coordinate.longitude, -93.2650, within: 0.1)
        expectClose(customRegionRT.serviceRect.height, 9485.2270, within: 0.1)
        expectClose(customRegionRT.serviceRect.width, 9453.3477, within: 0.1)
    }

    // MARK: - UmamiAnalyticsConfig inits

    func testUmamiConfig_memberwiseInit() {
        let config = UmamiAnalyticsConfig(url: URL(string: "https://analytics.example.com")!, id: "site-123")
        #expect(config.url.absoluteString == "https://analytics.example.com")
        #expect(config.id == "site-123")
    }

    func testUmamiConfig_failableInit_bothPresent() {
        let config = UmamiAnalyticsConfig(url: URL(string: "https://analytics.example.com"), id: "site-123")
        #expect(config?.id == "site-123")
    }

    func testUmamiConfig_failableInit_trimsID() {
        let config = UmamiAnalyticsConfig(url: URL(string: "https://analytics.example.com"), id: "  site-123 \n")
        #expect(config?.id == "site-123")
    }

    func testUmamiConfig_failableInit_partialPairsCollapseToNil() {
        #expect(UmamiAnalyticsConfig(url: nil, id: "site-123") == nil)
        #expect(UmamiAnalyticsConfig(url: URL(string: "https://analytics.example.com"), id: nil) == nil)
        #expect(UmamiAnalyticsConfig(url: URL(string: "https://analytics.example.com"), id: "") == nil)
        #expect(UmamiAnalyticsConfig(url: URL(string: "https://analytics.example.com"), id: "   ") == nil)
        #expect(UmamiAnalyticsConfig(url: nil, id: nil) == nil)
    }

    func testCustomRegions_creation_withSidecarAndUmami() {
        let region = Fixtures.customRegionWithSidecarAndUmami
        #expect(region.sidecarBaseURL?.absoluteString == "https://obaco.example.com")
        #expect(region.umamiAnalytics?.url.absoluteString == "https://analytics.example.com")
        #expect(region.umamiAnalytics?.id == "site-uuid-123")
    }

    func testCustomRegions_roundtripping_withSidecarAndUmami() {
        let plistData = try! PropertyListEncoder().encode([Fixtures.customRegionWithSidecarAndUmami])
        let rt = try! PropertyListDecoder().decode([Region].self, from: plistData)[0]

        #expect(rt.sidecarBaseURL?.absoluteString == "https://obaco.example.com")
        #expect(rt.umamiAnalytics?.url.absoluteString == "https://analytics.example.com")
        #expect(rt.umamiAnalytics?.id == "site-uuid-123")
        #expect(rt.isCustom == true)
    }
}
