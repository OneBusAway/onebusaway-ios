import Foundation
import SwiftUI
import CoreLocation
import Combine
import OBASharedCore
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
            var agencies: [OBAAgencyCoverage]?

            do {
                if !query.isEmpty {
                    do {
                        let placemarks = try await geocoder.geocodeAddressString(query)
                        if let location = placemarks.first?.location {
                            searchLocation = location
                        } else {
                            // Geocoding failed, try to get agency coverage
                            agencies = try await apiClient.fetchAgenciesWithCoverage()
                            if let agencyBound = agencies?.first?.agencyRegionBound {
                                searchRegion = agencyBound.serviceRect
                            }
                            await self.executeSearch(trimmed: query, location: locationProvider() ?? (agencies?.first.map { CLLocation(latitude: $0.centerLatitude, longitude: $0.centerLongitude) } ?? CLLocation(latitude: 0, longitude: 0)), searchRegion: searchRegion)
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
                        await self.executeSearch(trimmed: query, location: locationProvider() ?? defaultLocation, searchRegion: searchRegion)
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
                        await MainActor.run { self.errorMessage = "Location required for search" }
                        isLoading = false
                        return
                    }
                }

                let request = MKLocalSearch.Request()
                request.naturalLanguageQuery = query
                if let region = searchRegion {
                    request.region = MKCoordinateRegion(region)
                } else if let location = searchLocation {
                    request.region = MKCoordinateRegion(center: location.coordinate, latitudinalMeters: 40000, longitudinalMeters: 40000)
                }

                let search = MKLocalSearch(request: request)
                let response = try? await search.start()

                if let mapItem = response?.mapItems.first {
                    await self.executeSearch(trimmed: query, location: mapItem.placemark.location!, searchRegion: (mapItem.placemark.region as? CLCircularRegion)?.toMKMapRect())
                } else {
                    await self.executeSearch(trimmed: query, location: searchLocation!, searchRegion: searchRegion)
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
    }

    private func executeSearch(trimmed: String, location: CLLocation, searchRegion: MKMapRect?) async {
        do {
            let result = try await apiClient.fetchNearbyStops(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                radius: 5000.0
            )

            await MainActor.run {
                self.stops = result.stops.sorted { (s1: OBAStop, s2: OBAStop) in
                    let loc1 = CLLocation(latitude: s1.latitude, longitude: s1.longitude)
                    let loc2 = CLLocation(latitude: s2.latitude, longitude: s2.longitude)
                    let d1 = loc1.distance(from: location)
                    let d2 = loc2.distance(from: location)
                    return d1 < d2
                }
                if self.stops.isEmpty {
                    // If no error but no stops, keep empty list (view will show empty state)
                }
            }
        } catch {
            await MainActor.run {
                self.errorMessage = (error as? LocalizedError)?.errorDescription ?? "Unable to load stops."
            }
        }
    }
}
