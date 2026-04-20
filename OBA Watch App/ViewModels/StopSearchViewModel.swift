import Foundation
import SwiftUI
import CoreLocation
import Combine
import OBAKitCore
import MapKit

@MainActor
class StopSearchViewModel: ObservableObject {
    @Published var query: String
    @Published var stops: [OBAStop] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    private let apiClient: OBAAPIClient
    private let locationProvider: () -> CLLocation?
    private var searchTask: Task<Void, Never>?
    private let geocoder = CLGeocoder()

    init(initialQuery: String, apiClient: OBAAPIClient, locationProvider: @escaping () -> CLLocation?) {
        self.query = initialQuery
        self.apiClient = apiClient
        self.locationProvider = locationProvider
    }

    func performSearch() {
        searchTask?.cancel()

        isLoading = true
        errorMessage = nil
        stops = []

        searchTask = Task {
            var searchLocation: CLLocation?
            var searchRegion: MKMapRect?

            do {
                let resolved = try await LocationResolver.resolve(
                    query: query.isEmpty ? nil : query,
                    geocoder: geocoder,
                    apiClient: apiClient,
                    locationProvider: locationProvider
                )
                searchLocation = resolved.0
                searchRegion = resolved.1

                let request = MKLocalSearch.Request()
                request.naturalLanguageQuery = query
                if let region = searchRegion {
                    request.region = MKCoordinateRegion(region)
                } else if let location = searchLocation {
                    request.region = MKCoordinateRegion(center: location.coordinate, latitudinalMeters: 40000, longitudinalMeters: 40000)
                }

                let search = MKLocalSearch(request: request)
                var response: MKLocalSearch.Response?
                do {
                    response = try await search.start()
                } catch {
                    Logger.error("Search failed: \(error)")
                    self.errorMessage = (error as? LocalizedError)?.errorDescription ?? OBALoc("search.error.unexpected", value: "An unexpected error occurred during local search.", comment: "Unexpected error")
                    isLoading = false
                    return
                }

                if let mapItem = response?.mapItems.first, let loc = mapItem.placemark.location {
                    await self.executeSearch(trimmed: query, location: loc, searchRegion: (mapItem.placemark.region as? CLCircularRegion)?.toMKMapRect())
                } else if let searchLoc = searchLocation {
                    await self.executeSearch(trimmed: query, location: searchLoc, searchRegion: searchRegion)
                } else {
                    self.errorMessage = OBALoc("search.error.location_required", value: "Location required for search", comment: "Location required")
                }
            } catch {
                self.errorMessage = (error as? LocalizedError)?.errorDescription ?? OBALoc("common.error.unexpected", value: "An unexpected error occurred.", comment: "Unexpected error")
            }
            self.isLoading = false
        }
    }


    private func executeSearch(trimmed: String, location: CLLocation, searchRegion: MKMapRect?) async {
        do {
            let result = try await apiClient.fetchNearbyStops(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                radius: 5000.0
            )

            self.stops = result.stops.sorted { (s1: OBAStop, s2: OBAStop) in
                let loc1 = CLLocation(latitude: s1.latitude, longitude: s1.longitude)
                let loc2 = CLLocation(latitude: s2.latitude, longitude: s2.longitude)
                let d1 = loc1.distance(from: location)
                let d2 = loc2.distance(from: location)
                return d1 < d2
            }
        } catch {
            self.errorMessage = (error as? LocalizedError)?.errorDescription ?? OBALoc("search.error.unable_load_stops", value: "Unable to load stops.", comment: "Unable to load stops")
        }
    }
}
