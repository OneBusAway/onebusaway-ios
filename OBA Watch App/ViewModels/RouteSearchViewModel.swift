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
                        await self.executeSearch(trimmed: trimmed, location: locationProvider() ?? (agencies?.first.map { CLLocation(latitude: $0.centerLatitude, longitude: $0.centerLongitude) } ?? CLLocation(latitude: 0, longitude: 0)), searchRegion: searchRegion)
                        isLoading = false
                        return
                    }
                } catch {
                    // Geocoding failed, try to get agency coverage for default location
                    agencies = try await apiClient.fetchAgenciesWithCoverage()
                    let defaultLocation = agencies?.first.map { CLLocation(latitude: $0.centerLatitude, longitude: $0.centerLongitude) } ?? CLLocation(latitude: 0, longitude: 0)
                    if let agencyBound = agencies?.first?.agencyRegionBound {
                        searchRegion = agencyBound.serviceRect
                    }
                    await self.executeSearch(trimmed: trimmed, location: locationProvider() ?? defaultLocation, searchRegion: searchRegion)
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
                    await MainActor.run { self.errorMessage = "Location required for route search" }
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
                await MainActor.run {
                    self.errorMessage = (error as? LocalizedError)?.errorDescription ?? "An unexpected error occurred during local search."
                }
                isLoading = false
                return
            }

            if let mapItem = response?.mapItems.first {
                await self.executeSearch(trimmed: trimmed, location: mapItem.placemark.location!, searchRegion: (mapItem.placemark.region as? CLCircularRegion)?.toMKMapRect())
            } else {
                await self.executeSearch(trimmed: trimmed, location: searchLocation!, searchRegion: searchRegion)
            }
        } catch {
            await MainActor.run {
                self.errorMessage = (error as? LocalizedError)?.errorDescription ?? "An unexpected error occurred."
            }
        }
        
        await MainActor.run {
            self.isLoading = false
        }
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
            self.errorMessage = error.localizedDescription
        }
    }
}


