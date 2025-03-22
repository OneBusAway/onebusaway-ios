//
//  StopsViewModel.swift
//  OBAKit
//
//  Created by Prince Yadav on 06/03/25.
//

import Foundation
import CoreLocation
import Combine

class StopsViewModel: NSObject, ObservableObject {
    @Published var nearbyStops: [Stop] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var userLocation: CLLocation?
    
    private let apiService: APIServiceProtocol
    private let locationManager = CLLocationManager()
    private var cancellables = Set<AnyCancellable>()
    
    // Dependency injection for better testability
    init(apiService: APIServiceProtocol = APIService.shared) {
        self.apiService = apiService
        super.init()
        setupLocationManager()
    }
    
    private func setupLocationManager() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        locationManager.distanceFilter = 50 // Update when user moves 50 meters
    }
    
    func requestLocationAndLoadNearbyStops() {
        isLoading = true
        errorMessage = nil
        
        // Check if mock data should be used
        if UserDefaults.standard.bool(forKey: "useMockData") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                self.nearbyStops = Stop.examples
                self.isLoading = false
            }
            return
        }
        
        switch locationManager.authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            locationManager.requestLocation()
        case .denied, .restricted:
            isLoading = false
            errorMessage = "Location access is denied. Please enable location services in Settings."
        @unknown default:
            isLoading = false
            errorMessage = "Unknown location authorization status."
        }
    }
    
    func loadNearbyStops(latitude: Double, longitude: Double) {
        isLoading = true
        errorMessage = nil
        
        // Check if mock data should be used
        if UserDefaults.standard.bool(forKey: "useMockData") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                self.nearbyStops = Stop.examples
                self.isLoading = false
            }
            return
        }
        
        apiService.fetchNearbyStops(latitude: latitude, longitude: longitude)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] completion in
                self?.isLoading = false
                
                if case .failure(let error) = completion {
                    self?.errorMessage = error.localizedDescription
                }
            } receiveValue: { [weak self] stops in
                // Sort stops by distance
                self?.nearbyStops = stops.sorted {
                    ($0.distance ?? Double.infinity) < ($1.distance ?? Double.infinity)
                }
            }
            .store(in: &cancellables)
    }
    
    func refreshNearbyStops() async {
        // Check if mock data should be used
        if UserDefaults.standard.bool(forKey: "useMockData") {
            await MainActor.run {
                self.nearbyStops = Stop.examples
                self.isLoading = false
            }
            return
        }
        
        guard let location = locationManager.location else {
            await MainActor.run {
                errorMessage = "Unable to determine your location."
            }
            return
        }
        
        await MainActor.run {
            loadNearbyStops(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
        }
    }
    
    // Calculate distance between user and stop
    func calculateDistance(to stop: Stop) -> Double? {
        guard let userLocation = userLocation else { return nil }
        
        let stopLocation = CLLocation(latitude: stop.latitude, longitude: stop.longitude)
        return userLocation.distance(from: stopLocation)
    }
}

extension StopsViewModel: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        
        userLocation = location
        loadNearbyStops(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        isLoading = false
        errorMessage = "Failed to get your location: \(error.localizedDescription)"
    }
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            locationManager.requestLocation()
        case .denied, .restricted:
            isLoading = false
            errorMessage = "Location access is denied. Please enable location services in Settings."
        case .notDetermined:
            // Wait for the user to make a choice
            break
        @unknown default:
            isLoading = false
            errorMessage = "Unknown location authorization status."
        }
    }
}

