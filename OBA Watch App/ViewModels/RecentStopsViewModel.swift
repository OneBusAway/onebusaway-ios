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
    
    private let storage = WatchAppState.userDefaults
    private let storageKey = "OBASharedRecentStops"
    
    init() {
        loadRecentStops()
        
        // Listen for updates
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("RecentStopsUpdated"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.loadRecentStops()
        }
    }
    
    func loadRecentStops() {
        guard let data = storage.data(forKey: storageKey) else {
            recentStops = []
            return
        }

        let decoder = JSONDecoder()
        recentStops = (try? decoder.decode([OBAStop].self, from: data)) ?? []
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
        if let data = try? encoder.encode(recentStops) {
            storage.set(data, forKey: storageKey)
        }
    }
}

