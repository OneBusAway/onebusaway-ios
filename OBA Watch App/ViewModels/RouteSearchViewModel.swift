import Foundation
import CoreLocation
import Combine
import OBAKitCore
import MapKit


@MainActor
final class RouteSearchViewModel: ObservableObject {
    @Published var query: String
    @Published var routes: [OBARoute] = []
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
        searchTask = Task {
            await self._performSearch()
        }
    }

    private func _performSearch() async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        
        isLoading = true
        errorMessage = nil
        routes = []

        var searchLocation: CLLocation?
        var searchRegion: MKMapRect?

        do {
            do {
                let resolved = try await LocationResolver.resolve(query: trimmed.isEmpty ? nil : trimmed, geocoder: geocoder, apiClient: apiClient, locationProvider: locationProvider)
                searchLocation = resolved.0
                searchRegion = resolved.1
            } catch {
                self.errorMessage = error.watchOSUserFacingMessage
                isLoading = false
                return
            }

            if searchLocation == nil {
                self.errorMessage = OBALoc("search.error.location_required", value: "Location required for route search", comment: "Location required error message")
                isLoading = false
                return
            }

            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = trimmed
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
                self.errorMessage = (error as? LocalizedError)?.errorDescription ?? OBALoc("search.error.unexpected", value: "An unexpected error occurred during local search.", comment: "Unexpected error")
                isLoading = false
                return
            }

            if let mapItem = response?.mapItems.first, let loc = mapItem.placemark.location {
                await self.executeSearch(trimmed: trimmed, location: loc, searchRegion: (mapItem.placemark.region as? CLCircularRegion)?.toMKMapRect())
            } else if let searchLoc = searchLocation {
                await self.executeSearch(trimmed: trimmed, location: searchLoc, searchRegion: searchRegion)
            } else {
                self.errorMessage = OBALoc("search.error.location_required", value: "Location required for route search", comment: "Location required error message")
            }
        } catch {
            self.errorMessage = error.watchOSUserFacingMessage
        }
        
        self.isLoading = false
    }

    private func executeSearch(trimmed: String, location: CLLocation, searchRegion: MKMapRect?) async {
        do {
            let queryForAPI: String = trimmed.contains(" ") ? "" : trimmed
            let fetched = try await apiClient.searchRoutes(
                query: queryForAPI,
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                radius: 40000.0
            )
            self.routes = fetched
        } catch {
            self.errorMessage = error.watchOSUserFacingMessage
        }
    }
}
