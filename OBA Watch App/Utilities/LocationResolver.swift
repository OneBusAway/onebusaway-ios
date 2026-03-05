import Foundation
import CoreLocation
import MapKit
import OBAKitCore

struct LocationResolver {
    static func resolve(
        query: String?,
        geocoder: CLGeocoder,
        apiClient: OBAAPIClient,
        locationProvider: () -> CLLocation?
    ) async throws -> (CLLocation, MKMapRect?) {
        var searchLocation = locationProvider()
        var searchRegion: MKMapRect?
        var agencies: [OBAAgencyCoverage]?

        let trimmed = query?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty {
            do {
                let placemarks = try await geocoder.geocodeAddressString(trimmed)
                if let loc = placemarks.first?.location {
                    searchLocation = loc
                } else {
                    agencies = try await apiClient.fetchAgenciesWithCoverage()
                    if let bound = agencies?.first?.agencyRegionBound {
                        searchRegion = bound.serviceRect
                    }
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                agencies = try await apiClient.fetchAgenciesWithCoverage()
                if let bound = agencies?.first?.agencyRegionBound {
                    searchRegion = bound.serviceRect
                }
            }
        }

        if searchLocation == nil {
            if agencies == nil {
                agencies = try await apiClient.fetchAgenciesWithCoverage()
            }
            if let first = agencies?.first {
                searchLocation = CLLocation(latitude: first.centerLatitude, longitude: first.centerLongitude)
                searchRegion = first.agencyRegionBound.serviceRect
            }
        }

        guard let finalLocation = searchLocation else {
            throw NSError(domain: "LocationResolver", code: 1, userInfo: [NSLocalizedDescriptionKey: OBALoc("search.error.location_required", value: "Location required for search", comment: "Location required")])
        }
        return (finalLocation, searchRegion)
    }
}
