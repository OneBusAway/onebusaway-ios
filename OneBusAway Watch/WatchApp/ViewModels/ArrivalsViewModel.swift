//
//  ArrivalsViewModel.swift
//  OBAKit
//
//  Created by Prince Yadav on 06/03/25.
//

import Foundation
import Combine
import WatchKit

class ArrivalsViewModel: ObservableObject {
    @Published var arrivals: [Arrival] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var isFavorite = false
    @Published var lastUpdated = Date()
    
    private let apiService: APIServiceProtocol
    private var cancellables = Set<AnyCancellable>()
    private var refreshTimer: Timer?
    private var stopId: String?
    
    init(apiService: APIServiceProtocol = APIService.shared) {
        self.apiService = apiService
    }
    
    deinit {
        stopAutoRefresh()
    }
    
    func loadArrivals(for stopId: String) {
        self.stopId = stopId
        isLoading = true
        errorMessage = nil
        
        apiService.fetchArrivals(for: stopId)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] completion in
                self?.isLoading = false
                
                if case .failure(let error) = completion {
                    self?.errorMessage = error.localizedDescription
                }
            } receiveValue: { [weak self] arrivals in
                self?.arrivals = arrivals
                self?.lastUpdated = Date()
                
                // Provide haptic feedback for imminent arrivals
                self?.checkForImminentArrivals(arrivals)
            }
            .store(in: &cancellables)
    }
    
    func refreshArrivals() async {
        guard let stopId = stopId else { return }
        
        await MainActor.run {
            loadArrivals(for: stopId)
        }
    }
    
    func startAutoRefresh() {
        // Get refresh interval from user defaults
        let refreshInterval = UserDefaults.standard.integer(forKey: "refreshInterval")
        let interval = TimeInterval(refreshInterval > 0 ? refreshInterval : 30)
        
        refreshTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let self = self, let stopId = self.stopId else { return }
            self.loadArrivals(for: stopId)
        }
    }
    
    func stopAutoRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }
    
    func checkIfFavorite(stop: Stop) {
        let favoritesViewModel = FavoritesViewModel()
        favoritesViewModel.loadFavorites()
        
        isFavorite = favoritesViewModel.favoriteStops.contains { $0.id == stop.id }
    }
    
    func toggleFavorite(stop: Stop) {
        let favoritesViewModel = FavoritesViewModel()
        
        if isFavorite {
            favoritesViewModel.removeFavorite(stop: stop)
        } else {
            favoritesViewModel.addFavorite(stop: stop)
        }
        
        isFavorite.toggle()
        
        // Provide haptic feedback
        WKInterfaceDevice.current().play(.click)
    }
    
    private func checkForImminentArrivals(_ arrivals: [Arrival]) {
        // Check if notifications are enabled
        let enableNotifications = UserDefaults.standard.bool(forKey: "enableNotifications")
        let enableHapticFeedback = UserDefaults.standard.bool(forKey: "enableHapticFeedback")
        
        guard enableNotifications && enableHapticFeedback else { return }
        
        // Check for arrivals within 2 minutes
        let imminentArrivals = arrivals.filter { arrival in
            let arrivalTime = arrival.predictedArrivalTime ?? arrival.scheduledArrivalTime
            let timeUntilArrival = arrivalTime.timeIntervalSinceNow
            return timeUntilArrival > 0 && timeUntilArrival <= 120 // 2 minutes
        }
        
        if !imminentArrivals.isEmpty {
            // Provide haptic feedback for imminent arrivals
            WKInterfaceDevice.current().play(.notification)
        }
    }
}

