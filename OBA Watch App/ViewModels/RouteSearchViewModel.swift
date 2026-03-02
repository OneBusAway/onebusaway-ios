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
        var agencies: [OBAAgencyCoverage]?

        do {
            if !trimmed.isEmpty {
                do {
                    let placemarks = try await geocoder.geocodeAddressString(trimmed)
                    if let location = placemarks.first?.location {
                        searchLocation = location
                    } else {
                        // Geocoding failed, try to get agency coverage
                        agencies = try await apiClient.fetchAgenciesWithCoverage()
                        if let agencyBound = agencies?.first?.agencyRegionBound {
                            searchRegion = agencyBound.serviceRect
                        }
                        if agencies?.first != nil {
                            await self.executeSearch(trimmed: trimmed, location: locationProvider() ?? CLLocation(latitude: agencies!.first!.centerLatitude, longitude: agencies!.first!.centerLongitude), searchRegion: searchRegion)
                        } else if let location = locationProvider() {
                            await self.executeSearch(trimmed: trimmed, location: location, searchRegion: searchRegion)
                        } else {
                            self.errorMessage = OBALoc("search.error.location_required", value: "Location required for route search", comment: "Location required error message")
                        }
                        isLoading = false
                        return
                    }
                } catch {
                    // Geocoding failed, try to get agency coverage for default location
                    agencies = try await apiClient.fetchAgenciesWithCoverage()
                    if agencies?.first != nil {
                        await self.executeSearch(trimmed: trimmed, location: locationProvider() ?? CLLocation(latitude: agencies!.first!.centerLatitude, longitude: agencies!.first!.centerLongitude), searchRegion: searchRegion)
                    } else if let location = locationProvider() {
                        await self.executeSearch(trimmed: trimmed, location: location, searchRegion: searchRegion)
                    } else {
                        self.errorMessage = OBALoc("search.error.location_required", value: "Location required for route search", comment: "Location required error message")
                    }
                    isLoading = false
                    return
                }
            } else {
                searchLocation = locationProvider()
            }

            if searchLocation == nil {
                // If no searchLocation yet, try to get it from agency coverage
                if agencies == nil {
                    agencies = try await apiClient.fetchAgenciesWithCoverage()
                }
                if let first = agencies?.first {
                    searchLocation = CLLocation(latitude: first.centerLatitude, longitude: first.centerLongitude)
                    searchRegion = first.agencyRegionBound.serviceRect
                } else {
                    self.errorMessage = OBALoc("search.error.location_required", value: "Location required for route search", comment: "Location required error message")
                    isLoading = false
                    return
                }
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
                self.errorMessage = (error as? LocalizedError)?.errorDescription ?? "An unexpected error occurred during local search."
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

