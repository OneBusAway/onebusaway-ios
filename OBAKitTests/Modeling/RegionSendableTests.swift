//
//  RegionSendableTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import MapKit
import Testing
@testable import OBAKitCore

@MainActor
@Suite(.serialized)
final class RegionSendableTests {

    @Test func `Region and Agency are statically Sendable and thread safe`() async throws {
        let region: Region = Fixtures.customMinneapolisRegion
        let agenciesPayload = try Fixtures.loadRESTAPIPayload(type: [AgencyWithCoverage].self, fileName: "agencies_with_coverage.json")
        let agency: Agency = try #require(agenciesPayload.first?.agency)

        // Verify transfer across actor boundary without warnings or races
        let regionTask = Task.detached { () -> (String, Int, MKMapRect) in
            return (region.name, region.regionIdentifier, region.serviceRect)
        }
        let agencyTask = Task.detached { () -> (String, String) in
            return (agency.name, agency.id)
        }

        let (regionName, regionID, serviceRect) = await regionTask.value
        let (agencyName, agencyID) = await agencyTask.value

        #expect(regionName == region.name)
        #expect(regionID == region.regionIdentifier)
        #expect(!serviceRect.isNull)
        #expect(agencyName == agency.name)
        #expect(agencyID == agency.id)

        // Concurrent reads across multiple tasks
        await withTaskGroup(of: Bool.self) { group in
            for _ in 0..<10 {
                group.addTask {
                    let _ = region.serviceRect
                    let _ = region.centerCoordinate
                    let _ = region.isBikeshareEnabled
                    let _ = agency.resolvedTimeZone
                    let _ = agency.cleanedPhoneNumber()
                    return true
                }
            }
        }
    }

    @Test func `Region and Agency JSON encode and decode round trip`() throws {
        let region = Fixtures.customMinneapolisRegion
        let encodedRegion = try JSONEncoder.RESTEncoder().encode(region)
        let decodedRegion = try JSONDecoder.RESTDecoder().decode(Region.self, from: encodedRegion)

        #expect(decodedRegion.name == region.name)
        #expect(decodedRegion.regionIdentifier == region.regionIdentifier)
        #expect(MKMapRectEqualToRect(decodedRegion.serviceRect, region.serviceRect))
        #expect(decodedRegion == region)

        let agenciesPayload = try Fixtures.loadRESTAPIPayload(type: [AgencyWithCoverage].self, fileName: "agencies_with_coverage.json")
        let agency = try #require(agenciesPayload.first?.agency)
        let encodedAgency = try JSONEncoder.RESTEncoder().encode(agency)
        let decodedAgency = try JSONDecoder.RESTDecoder().decode(Agency.self, from: encodedAgency)

        #expect(decodedAgency.id == agency.id)
        #expect(decodedAgency.name == agency.name)
        #expect(decodedAgency.agencyURL == agency.agencyURL)
        #expect(decodedAgency.phone == agency.phone)
        #expect(decodedAgency.timeZone == agency.timeZone)
        #expect(decodedAgency.language == agency.language)
        #expect(decodedAgency.isPrivateService == agency.isPrivateService)
        #expect(decodedAgency.email == agency.email)
        #expect(decodedAgency.disclaimer == agency.disclaimer)
        #expect(decodedAgency.fareURL == agency.fareURL)
    }
}
