import Foundation
import SwiftUI
import MapKit
import OBAKitCore

@MainActor
class TripPlanningViewModel: ObservableObject {
    @Published var itineraries: [OTPItinerary] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let appState: WatchAppState
    
    init(appState: WatchAppState = .shared) {
        self.appState = appState
    }
    
    func planTrip(from origin: CLLocationCoordinate2D, to destination: CLLocationCoordinate2D) async {
        guard let otpURL = appState.currentOTPBaseURL else {
            self.errorMessage = OBALoc("trip_planning.error.unavailable_region", value: "Trip planning is not available in this region.", comment: "Error message when trip planning offline/unsupported")
            return
        }
        
        isLoading = true
        defer { isLoading = false }
        errorMessage = nil
        
        do {
            self.itineraries = try await OTPService.shared.planTrip(baseURL: otpURL, from: origin, to: destination)
        } catch {
            self.errorMessage = error.watchOSUserFacingMessage
        }
    }
}
