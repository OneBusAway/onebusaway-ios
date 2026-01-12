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
                    errorMessage = "Location unavailable"
                    return
                }
            } catch {
                errorMessage = "Location unavailable"
                return
            }
        }

        do {
            let span = 0.05
            let vehicles = try await apiClient.fetchVehiclesReliably(
                latitude: searchLocation!.coordinate.latitude,
                longitude: searchLocation!.coordinate.longitude,
                latSpan: span,
                lonSpan: span
            )
            
            self.nearbyVehicles = vehicles
            if vehicles.isEmpty {
                self.errorMessage = "No active vehicles found nearby."
            }
        } catch {
            self.errorMessage = (error as? LocalizedError)?.errorDescription ?? "Unable to load nearby vehicles."
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
            var agencies: [OBAAgencyCoverage]?

            do {
                // Attempt to geocode the query first
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
                        }
                    } catch {
                        print("Geocoding failed for '\(trimmed)': \(error.localizedDescription). Attempting MKLocalSearch.")
                        // Geocoding failed, try to get agency coverage for default location
                        agencies = try await apiClient.fetchAgenciesWithCoverage()
                        if let agencyBound = agencies?.first?.agencyRegionBound {
                            searchRegion = agencyBound.serviceRect
                        }
                    }
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

                if let mapItem = response?.mapItems.first, let location = mapItem.placemark.location {
                    await self.fetchNearbyVehicles(at: location)
                } else {
                    // If MKLocalSearch failed or no location found, treat as vehicle ID
                    do {
                        print("Fetching vehicle with ID: \(trimmed)")
                        let v = try await apiClient.fetchVehicle(vehicleID: trimmed)
                        await MainActor.run {
                            self.vehicle = v
                            self.errorMessage = nil
                            print("Successfully fetched vehicle: \(v)")
                        }
                    } catch {
                        await MainActor.run {
                            if let decodingError = error as? DecodingError {
                                print("Decoding error (likely 404/Null response): \(decodingError)")
                            } else {
                                print("Error fetching vehicle: \(error)")
                            }

                            if let urlError = error as? URLError {
                                switch urlError.code {
                                case .notConnectedToInternet, .networkConnectionLost:
                                    self.errorMessage = "No internet connection"
                                case .timedOut:
                                    self.errorMessage = "Request timed out"
                                case .badServerResponse:
                                    self.errorMessage = "Vehicle '\(trimmed)' not found"
                                default:
                                    self.errorMessage = "Unable to connect. Please check your network connection."
                                }
                            } else if error is DecodingError {
                                self.errorMessage = "Vehicle '\(trimmed)' not found"
                            } else {
                                let errorDesc = error.localizedDescription
                                if errorDesc.lowercased().contains("not found") || errorDesc.contains("404") {
                                    self.errorMessage = "Vehicle '\(trimmed)' not found"
                                } else if errorDesc.isEmpty {
                                    self.errorMessage = "Vehicle not found"
                                } else {
                                    self.errorMessage = "Unable to load vehicle information"
                                }
                            }
                            self.vehicle = nil
                        }
                    }
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
}
