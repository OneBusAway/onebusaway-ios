//
//  TripDetailsViewModel.swift
//  OBAWatch Watch App
//
//  Created by Prince Yadav on 31/12/25.
//

import Foundation
import SwiftUI
import Combine
import OBAKitCore

import CoreLocation
import MapKit

@MainActor
class TripDetailsViewModel: ObservableObject {
    @Published var tripDetails: OBATripExtendedDetails?
    @Published var polyline: [CLLocationCoordinate2D] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let apiClient: OBAAPIClient
    private var tripID: String
    private let vehicleID: String?
    private let initialTrip: OBATripForLocation?
    
    init(apiClient: OBAAPIClient, tripID: String, vehicleID: String? = nil, initialTrip: OBATripForLocation? = nil) {
        self.apiClient = apiClient
        self.tripID = tripID
        self.vehicleID = vehicleID
        self.initialTrip = initialTrip
        
        // If we have an initial trip, use its status immediately
        if let trip = initialTrip {
            self.tripDetails = OBATripExtendedDetails(
                tripId: trip.id,
                serviceDate: nil,
                frequency: nil,
                status: trip.toStatus,
                schedule: nil
            )
        }
    }
    
    func loadDetails() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        
        do {
            var tripIDToFetch = tripID
            
            // If tripID is missing but we have a vehicleID, try to find the current trip for that vehicle
            if tripIDToFetch.isEmpty, let vID = vehicleID, !vID.isEmpty {
                do {
                    let vehicle = try await apiClient.fetchVehicle(vehicleID: vID)
                    if let tID = vehicle.tripID, !tID.isEmpty {
                        tripIDToFetch = tID
                        self.tripID = tID
                    } else {
                        errorMessage = String(format: OBALoc("trip_details.error.vehicle_not_on_trip_fmt", value: "Vehicle %@ is not currently on an active trip.", comment: "Vehicle not on active trip"), vID)
                        return
                    }
                } catch {
                    errorMessage = String(format: OBALoc("trip_details.error.unable_find_trip_fmt", value: "Unable to find trip for vehicle %@.", comment: "Unable to find trip for vehicle"), vID)
                    return
                }
            }
            
            if tripIDToFetch.isEmpty {
                errorMessage = OBALoc("trip_details.error.no_trip_info", value: "No trip information available.", comment: "No trip info available")
                return
            }

            // Fetch trip details for schedule/stops
            let details = try await apiClient.fetchTripDetails(tripID: tripIDToFetch)
            
            // Preserve status if the new details don't have it but we have one
            var finalStatus = details.status ?? self.tripDetails?.status
            
            // If status is still missing from trip details, but we have a vehicleID, try to fetch it
            if finalStatus == nil, let vID = vehicleID, !vID.isEmpty {
                do {
                    let vehicleStatus = try await apiClient.fetchTripForVehicle(vehicleID: vID)
                    finalStatus = vehicleStatus.status
                } catch {
                    Logger.error("fetchTripForVehicle failed for \(vID): \(error)")
                }
            }
            
            self.tripDetails = OBATripExtendedDetails(
                tripId: details.tripId,
                serviceDate: details.serviceDate,
                frequency: details.frequency,
                status: finalStatus,
                schedule: details.schedule
            )
            
            // Fetch trip info for shapeID
            let tripInfo = try await apiClient.fetchTrip(tripID: tripIDToFetch)
            if let shapeID = tripInfo.shapeID {
                let encodedPolyline = try await apiClient.fetchShape(shapeID: shapeID)
                self.polyline = OBAURLSessionAPIClient.decodePolyline(encodedPolyline)
            } else if let stopTimes = details.schedule?.stopTimes {
                // Fallback: if no shape, use stop coordinates as a basic line
                self.polyline = stopTimes.compactMap { stopTime -> CLLocationCoordinate2D? in
                    guard let lat = stopTime.latitude, let lon = stopTime.longitude else { return nil }
                    return CLLocationCoordinate2D(latitude: lat, longitude: lon)
                }
            }
        } catch {
            errorMessage = error.watchOSUserFacingMessage
        }
    }
}
