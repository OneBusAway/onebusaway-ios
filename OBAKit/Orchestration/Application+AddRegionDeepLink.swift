//
//  Application+AddRegionDeepLink.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import MapKit
import OBAKitCore

/// `onebusaway://add-region?…`: add a custom region from a link and switch to it.
extension Application {

    /// Adds the region `regionData` describes and makes it the current region.
    ///
    /// Throws if the region can't be added; the caller tells the rider the link was invalid.
    @MainActor
    func addCustomRegion(from regionData: AddRegionURLData) async throws {
        guard let regionCoordinate = try await apiService?.getAgenciesWithCoverage().list.first?.region else {
            return
        }

        // Adjustments for coordinate span
        var adjustedRegionCoordinate = regionCoordinate
        adjustedRegionCoordinate.span.latitudeDelta = 2
        adjustedRegionCoordinate.span.longitudeDelta = 2

        // Create region provider
        let regionProvider = RegionPickerCoordinator(regionsService: regionsService, userDataStore: userDataStore)

        // Construct Region from URL data. umamiAnalytics applies the
        // both-or-nothing rule; no rule logic lives here.
        //
        // regionIdentifier must come from the link: Region falls back to a
        // random id when it's nil, and every Obaco call for the region then
        // 404s against an id the sidecar has never heard of.
        let currentRegion = Region(
            name: regionData.name,
            OBABaseURL: regionData.obaURL,
            coordinateRegion: adjustedRegionCoordinate,
            contactEmail: "example@example.com",
            regionIdentifier: regionData.regionID,
            openTripPlannerURL: regionData.otpURL,
            openTripPlannerGraphQLURL: regionData.otpGraphQLURL,
            supportsOTPGraphQLBikeshare: regionData.supportsOTPGraphQLBikeshare,
            sidecarBaseURL: regionData.sidecarURL,
            umamiAnalytics: regionData.umamiAnalytics)

        // Add and set current region
        try await regionProvider.add(customRegion: currentRegion)
        try await regionProvider.setCurrentRegion(to: currentRegion)
    }
}
