//
//  TripDetailsViewModel.swift
//  OBAWatch Watch App
//
//  Created by Prince Yadav on 31/12/25.
//

import Foundation
import SwiftUI
import Combine
import OBASharedCore

@MainActor
class TripDetailsViewModel: ObservableObject {
    @Published var tripDetails: OBATripExtendedDetails?
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let apiClient: OBAAPIClient
    private let tripID: String
    private let vehicleID: String?
    
    init(apiClient: OBAAPIClient, tripID: String, vehicleID: String? = nil) {
        self.apiClient = apiClient
        self.tripID = tripID
        self.vehicleID = vehicleID
    }
    
    func loadDetails() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        
        do {
            let details = try await apiClient.fetchTripDetails(tripID: tripID)
            self.tripDetails = details
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
