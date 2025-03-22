//
//  FavoritesViewModel.swift
//  OBAKit
//
//  Created by Prince Yadav on 06/03/25.
//


import Foundation
import Combine
import WatchKit

class FavoritesViewModel: ObservableObject {
    @Published var favoriteStops: [Stop] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let apiService = APIService.shared
    private let connectivityService = WatchConnectivityService.shared
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        // Listen for favorites updates from iPhone
        connectivityService.$receivedFavorites
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] favorites in
                guard let self = self, !favorites.isEmpty else { return }
                self.saveFavorites(favorites)
                self.loadFavorites()
            }
            .store(in: &cancellables)
    }
    
    func loadFavorites() {
        isLoading = true
        
        // Load favorites from UserDefaults
        if let data = UserDefaults.standard.data(forKey: "favoriteStops") {
            do {
                let favorites = try JSONDecoder().decode([Stop].self, from: data)
                self.favoriteStops = favorites
            } catch {
                errorMessage = "Failed to load favorites: \(error.localizedDescription)"
            }
        }
        
        isLoading = false
    }
    
    func addFavorite(stop: Stop) {
        // Check if stop is already a favorite
        guard !favoriteStops.contains(where: { $0.id == stop.id }) else { return }
        
        // Add to favorites
        favoriteStops.append(stop)
        
        // Save to UserDefaults
        saveFavorites(favoriteStops)
        
        // Sync with iPhone
        connectivityService.sendFavoritesToPhone(favoriteStops)
        
        // Provide haptic feedback
        WKInterfaceDevice.current().play(.success)
    }
    
    func removeFavorite(at indexSet: IndexSet) {
        // Remove from favorites
        favoriteStops.remove(atOffsets: indexSet)
        
        // Save to UserDefaults
        saveFavorites(favoriteStops)
        
        // Sync with iPhone
        connectivityService.sendFavoritesToPhone(favoriteStops)
        
        // Provide haptic feedback
        WKInterfaceDevice.current().play(.success)
    }
    
    func removeFavorite(stop: Stop) {
        // Find index of stop
        if let index = favoriteStops.firstIndex(where: { $0.id == stop.id }) {
            removeFavorite(at: IndexSet(integer: index))
        }
    }
    
    private func saveFavorites(_ favorites: [Stop]) {
        do {
            let data = try JSONEncoder().encode(favorites)
            UserDefaults.standard.set(data, forKey: "favoriteStops")
        } catch {
            errorMessage = "Failed to save favorites: \(error.localizedDescription)"
        }
    }
    
    func refreshFavorites() async {
        await MainActor.run {
            loadFavorites()
        }
    }
}

