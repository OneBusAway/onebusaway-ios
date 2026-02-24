import Foundation
import SwiftUI
import MapKit
import OBAKitCore

@MainActor
@Observable
class TripPlanningViewModel {
    var itineraries: [OTPItinerary] = []
    var isLoading = false
    var error: Error?
    
    private let appState: WatchAppState
    
    init(appState: WatchAppState = .shared) {
        self.appState = appState
    }
    
    func planTrip(from origin: CLLocationCoordinate2D, to destination: CLLocationCoordinate2D) async {
        guard let otpURL = appState.currentOTPBaseURL else {
            self.error = NSError(domain: "TripPlanning", code: 1, userInfo: [NSLocalizedDescriptionKey: "Trip planning is not available in this region."])
            return
        }
        
        isLoading = true
        error = nil
        
        do {
            self.itineraries = try await OTPService.shared.planTrip(baseURL: otpURL, from: origin, to: destination)
        } catch {
            self.error = error
        }
        
        isLoading = false
    }
}
