import Foundation
import Combine
import CoreLocation
import OBASharedCore

@MainActor
final class VehiclesViewModel: ObservableObject {
    @Published var trips: [OBATripForLocation] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    private let apiClient: OBAAPIClient
    private let locationProvider: () -> CLLocation?
    init(apiClient: OBAAPIClient, locationProvider: @escaping () -> CLLocation?) {
        self.apiClient = apiClient
        self.locationProvider = locationProvider
    }
    func loadNearbyVehicles() async {
        guard let loc = locationProvider() else {
            errorMessage = "Location not available"
            return
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let span = 0.02
            let result = try await apiClient.fetchTripsForLocation(
                latitude: loc.coordinate.latitude,
                longitude: loc.coordinate.longitude,
                latSpan: span,
                lonSpan: span
            )
            trips = result.sorted { ($0.lastUpdateTime ?? .distantPast) > ($1.lastUpdateTime ?? .distantPast) }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
