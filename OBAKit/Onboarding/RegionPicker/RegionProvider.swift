//
//  RegionProvider.swift
//  OBAKit
//
//  Created by Alan Chu on 1/23/23.
//

import CoreLocation
import OBAKitCore

public protocol RegionProvider: ObservableObject {
    /// OBA-regions and custom regions.
    var allRegions: [Region] { get }
    var currentRegion: Region? { get }

    /// The user's most recent location, if available.
    var currentLocation: CLLocation? { get }

    var automaticallySelectRegion: Bool { get set }

    func refreshRegions() async throws

    /// A ``currentRegion`` setter that is `async throws`.
    func setCurrentRegion(to newRegion: Region) async throws

    /// Adds the provided custom region to the RegionsService.
    func add(customRegion newRegion: Region) async throws

    /// Deletes the provided custom region.
    func delete(customRegion region: Region) async throws

    /// Fetches the agencies served by the OneBusAway server at `baseURL`.
    /// Used to validate a custom region's server before saving it.
    func fetchAgenciesWithCoverage(baseURL: URL) async throws -> [AgencyWithCoverage]

    /// Returns whether trip planning is enabled for the specified region.
    func isTripPlanningEnabled(for region: Region) -> Bool

    /// Sets trip planning enabled/disabled for the specified region.
    func setTripPlanningEnabled(_ enabled: Bool, for region: Region)
}
