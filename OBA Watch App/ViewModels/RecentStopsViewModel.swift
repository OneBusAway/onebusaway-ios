//
//  RecentStopsViewModel.swift
//  OBAWatch Watch App
//
//  Created by Prince Yadav on 31/12/25.
//

import Foundation
import SwiftUI
import Combine
import OBAKitCore
@MainActor
class RecentStopsViewModel: ObservableObject {
    @Published var recentStops: [OBAStop] = []
    
    static let shared = RecentStopsViewModel()
    
    private let storage = WatchAppState.userDefaults
    private let storageKey = "OBASharedRecentStops"
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        loadRecentStops()
        
        // Listen for updates
        NotificationCenter.default.publisher(for: .RecentStopsUpdated)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.loadRecentStops()
            }
            .store(in: &cancellables)
    }
    
    func loadRecentStops() {
        guard let data = storage.data(forKey: storageKey) else {
            recentStops = []
            return
        }

        let decoder = JSONDecoder()
        do {
            recentStops = try decoder.decode([OBAStop].self, from: data)
        } catch {
            Logger.error("Failed to decode recent stops: \(error)")
            recentStops = []
        }
    }

    func addRecentStop(_ stop: OBAStop) {
        var current = recentStops
        if let idx = current.firstIndex(where: { $0.id == stop.id }) {
            current.remove(at: idx)
        }
        current.insert(stop, at: 0)
        recentStops = Array(current.prefix(20))
        save()
    }

    func removeRecentStop(at offsets: IndexSet) {
        recentStops.remove(atOffsets: offsets)
        save()
    }

    private func save() {
        let encoder = JSONEncoder()
        do {
            let data = try encoder.encode(recentStops)
            storage.set(data, forKey: storageKey)
        } catch {
            Logger.error("Failed to encode recent stops: \(error)")
        }
    }
}
