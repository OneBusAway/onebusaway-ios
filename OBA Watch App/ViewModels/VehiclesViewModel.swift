import Foundation
import Combine
import CoreLocation
import OBAKitCore

@MainActor
final class VehiclesViewModel: ObservableObject {
    @Published var trips: [OBATripForLocation] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    private let apiClientProvider: () -> OBAAPIClient
    private let locationProvider: () -> CLLocation?
    init(apiClientProvider: @escaping () -> OBAAPIClient, locationProvider: @escaping () -> CLLocation?) {
        self.apiClientProvider = apiClientProvider
        self.locationProvider = locationProvider
    }
    func loadNearbyVehicles() async {
        let apiClient = apiClientProvider()
        guard let loc = locationProvider() else {
            errorMessage = "Location not available"
            return
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let span = 0.015 // ~1.5km span, better for trips-for-location compatibility
            let result = try await apiClient.fetchVehiclesReliably(
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
