//
//  ComplicationProvider.swift
//  OBAKit
//
//  Created by Prince Yadav on 06/03/25.
//


import WidgetKit
import SwiftUI
import Combine

class ComplicationProvider: TimelineProvider {
    typealias Entry = ComplicationEntry
    
    private let apiService = APIService.shared
    private var cancellables = Set<AnyCancellable>()
    
    func placeholder(in context: Context) -> ComplicationEntry {
        ComplicationEntry.placeholder
    }
    
    func getSnapshot(in context: Context, completion: @escaping (ComplicationEntry) -> Void) {
        if context.isPreview {
            completion(ComplicationEntry.placeholder)
            return
        }
        
        if let data = UserDefaults.standard.data(forKey: "favoriteStops"),
           let favorites = try? JSONDecoder().decode([Stop].self, from: data),
           let firstFavorite = favorites.first {
            
            fetchArrivalsForComplication(stopId: firstFavorite.id, completion: completion)
        } else {
            completion(ComplicationEntry.empty)
        }
    }
    
    func getTimeline(in context: Context, completion: @escaping (Timeline<ComplicationEntry>) -> Void) {
        if let data = UserDefaults.standard.data(forKey: "favoriteStops"),
           let favorites = try? JSONDecoder().decode([Stop].self, from: data),
           let firstFavorite = favorites.first {
            
            fetchArrivalsForComplication(stopId: firstFavorite.id) { entry in
                let refreshDate = Date().addingTimeInterval(15 * 60) // Refresh every 15 minutes
                let timeline = Timeline(entries: [entry], policy: .after(refreshDate))
                completion(timeline)
            }
        } else {
            let entry = ComplicationEntry.empty
            let timeline = Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(15 * 60)))
            completion(timeline)
        }
    }
    
    private func fetchArrivalsForComplication(stopId: String, completion: @escaping (ComplicationEntry) -> Void) {
        apiService.fetchArrivals(for: stopId)
            .receive(on: DispatchQueue.main)
            .sink { completionResult in
                if case .failure = completionResult {
                    completion(ComplicationEntry.empty)
                }
            } receiveValue: { arrivals in
                if let nextArrival = arrivals.first {
                    let entry = ComplicationEntry(date: Date(), arrival: nextArrival)
                    completion(entry)
                } else {
                    completion(ComplicationEntry.empty)
                }
            }
            .store(in: &cancellables) // ✅ Now allowed because 'self' is mutable in a class
    }
}
