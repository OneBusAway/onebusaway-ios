import Foundation
import Combine
import CoreLocation
import OBASharedCore

@MainActor
final class RouteDetailViewModel: ObservableObject {
    @Published var directions: [OBARouteDirection] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var shapeCoordinates: [CLLocationCoordinate2D] = []

    private let apiClient: OBAAPIClient
    private let routeID: OBARouteID

    init(apiClient: OBAAPIClient, routeID: OBARouteID) {
        self.apiClient = apiClient
        self.routeID = routeID
    }

    func load() async {
        isLoading = true
        errorMessage = nil

        do {
            let result = try await apiClient.fetchStopsForRoute(routeID: routeID)
            directions = result

            if let shapeID = try await apiClient.fetchShapeIDForRoute(routeID: routeID) {
                let encoded = try await apiClient.fetchShape(shapeID: shapeID)
                shapeCoordinates = PolylineDecoder.decode(encodedPolyline: encoded)
            }
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Unable to load route stops."
        }

        isLoading = false
    }
}
