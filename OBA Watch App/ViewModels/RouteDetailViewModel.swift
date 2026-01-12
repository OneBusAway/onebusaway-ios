import Foundation
import Combine
import CoreLocation
import OBAKitCore

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
            // 1. Fetch stops for route
            let result = try await apiClient.fetchStopsForRoute(routeID: routeID)
            directions = result

            // 2. Fetch shape ID and path (optional, don't fail if this fails)
            do {
                if let shapeID = try await apiClient.fetchShapeIDForRoute(routeID: routeID) {
                    let encoded = try await apiClient.fetchShape(shapeID: shapeID)
                    shapeCoordinates = PolylineDecoder.decode(encodedPolyline: encoded)
                }
            } catch {
                print("Note: Could not load route shape: \(error)")
                // We don't set errorMessage here because stops are more important
            }
        } catch let apiError as OBAAPIError {
            print("API Error loading route stops: \(apiError)")
            errorMessage = apiError.errorDescription ?? "API Error"
        } catch {
            print("Error loading route stops: \(error)")
            if let urlError = error as? URLError {
                errorMessage = "Network error: \(urlError.localizedDescription)"
            } else if error is DecodingError {
                errorMessage = "Data format error from server."
            } else {
                errorMessage = error.localizedDescription
            }
        }

        isLoading = false
    }
}
