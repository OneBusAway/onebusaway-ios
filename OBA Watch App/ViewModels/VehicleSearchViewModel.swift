import Foundation
import CoreLocation
import Combine
import OBAKitCore
import MapKit

@MainActor
final class VehicleSearchViewModel: ObservableObject {
    @Published var query: String
    @Published var vehicle: OBAVehicle?
    @Published var nearbyVehicles: [OBATripForLocation] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    private let apiClient: OBAAPIClient
    private let locationProvider: () -> CLLocation?
    private var searchTask: Task<Void, Never>?
    private let geocoder = CLGeocoder()

    init(
        initialQuery: String,
        apiClient: OBAAPIClient,
        locationProvider: @escaping () -> CLLocation?
    ) {
        self.query = initialQuery
        self.apiClient = apiClient
        self.locationProvider = locationProvider
    }

    func fetchNearbyVehicles(at location: CLLocation? = nil) async {
        isLoading = true
        errorMessage = nil
        nearbyVehicles = []

        defer {
            isLoading = false
        }

        var searchLocation = location
        if searchLocation == nil {
            searchLocation = locationProvider()
        }

        if searchLocation == nil {
            do {
                let agencies = try await apiClient.fetchAgenciesWithCoverage()
                if let first = agencies.first {
                    searchLocation = CLLocation(latitude: first.centerLatitude, longitude: first.centerLongitude)
                } else {
                    errorMessage = OBALoc("vehicle_search.error.location_unavailable", value: "Location unavailable", comment: "Location unavailable")
                    return
                }
            } catch {
                errorMessage = OBALoc("vehicle_search.error.location_unavailable", value: "Location unavailable", comment: "Location unavailable")
                return
            }
        }

        guard let resolvedLocation = searchLocation else {
            errorMessage = OBALoc("vehicle_search.error.location_unavailable", value: "Location unavailable", comment: "Location unavailable")
            return
        }

        do {
            let span = 0.015
            let vehicles = try await apiClient.fetchVehiclesReliably(
                latitude: resolvedLocation.coordinate.latitude,
                longitude: resolvedLocation.coordinate.longitude,
                latSpan: span,
                lonSpan: span
            )
            
            self.nearbyVehicles = vehicles
            if vehicles.isEmpty {
                self.errorMessage = OBALoc("vehicle_search.error.none_nearby", value: "No active vehicles found nearby.", comment: "No vehicles found")
            }
        } catch {
            self.errorMessage = (error as? LocalizedError)?.errorDescription ?? OBALoc("vehicle_search.error.unable_load_nearby", value: "Unable to load nearby vehicles.", comment: "Unable to load vehicles")
        }
    }

    func performSearch() {
        searchTask?.cancel()

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            vehicle = nil
            errorMessage = nil
            Task { await fetchNearbyVehicles() }
            return
        }

        isLoading = true
        errorMessage = nil
        vehicle = nil
        nearbyVehicles = []

        searchTask = Task {
            var searchLocation: CLLocation?
            var searchRegion: MKMapRect?

            do {
                do {
                    let resolved = try await LocationResolver.resolve(query: trimmed, geocoder: geocoder, apiClient: apiClient, locationProvider: locationProvider)
                    searchLocation = resolved.0
                    searchRegion = resolved.1
                } catch {
                    self.errorMessage = error.watchOSUserFacingMessage
                    self.isLoading = false
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
                    self.isLoading = false
                    return
                }

                if let mapItem = response?.mapItems.first, let location = mapItem.placemark.location {
                    await self.fetchNearbyVehicles(at: location)
                } else {
                    // If MKLocalSearch failed or no location found, treat as vehicle ID
                    do {
                        let v = try await apiClient.fetchVehicle(vehicleID: trimmed)
                        self.vehicle = v
                        self.errorMessage = nil
                    } catch {
                        if let urlError = error as? URLError {
                            switch urlError.code {
                            case .notConnectedToInternet, .networkConnectionLost:
                                self.errorMessage = OBALoc("common.error.no_internet", value: "No internet connection", comment: "No internet")
                            case .timedOut:
                                self.errorMessage = OBALoc("common.error.timed_out", value: "Request timed out", comment: "Timed out")
                            case .badServerResponse:
                                self.errorMessage = String(format: OBALoc("vehicle_search.error.not_found_fmt", value: "Vehicle '%@' not found", comment: "Vehicle not found"), trimmed)
                            default:
                                self.errorMessage = OBALoc("common.error.unable_connect", value: "Unable to connect. Please check your network connection.", comment: "Unable to connect")
                            }
                        } else if error is DecodingError {
                            self.errorMessage = String(format: OBALoc("vehicle_search.error.not_found_fmt", value: "Vehicle '%@' not found", comment: "Vehicle not found"), trimmed)
                        } else {
                            let errorDesc = error.localizedDescription
                            if errorDesc.lowercased().contains("not found") || errorDesc.contains("404") {
                                self.errorMessage = String(format: OBALoc("vehicle_search.error.not_found_fmt", value: "Vehicle '%@' not found", comment: "Vehicle not found"), trimmed)
                            } else if errorDesc.isEmpty {
                                self.errorMessage = OBALoc("vehicle_search.error.not_found", value: "Vehicle not found", comment: "Vehicle not found")
                            } else {
                                self.errorMessage = OBALoc("vehicle_search.error.unable_load", value: "Unable to load vehicle information", comment: "Unable to load vehicle")
                            }
                        }
                        self.vehicle = nil
                    }
                }
            } catch {
                self.errorMessage = (error as? LocalizedError)?.errorDescription ?? OBALoc("common.error.unexpected", value: "An unexpected error occurred.", comment: "Unexpected error")
            }

            self.isLoading = false
        }
    }
}
