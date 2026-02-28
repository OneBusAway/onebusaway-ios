//
//  SearchViewModel.swift
//  OBAWatch Watch App
//
//  Created by Prince Yadav on 31/12/25.
//

import Foundation
import SwiftUI
import CoreLocation
import Combine
import OBAKitCore
@MainActor
class SearchViewModel: ObservableObject {
    @Published var searchText: String = ""
    @Published var searchResults: [OBAStop] = []
    @Published var bookmarkResults: [WatchBookmark] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var recentStops: [OBAStop] = []
    @Published var recentSearchTerms: [String] = []
    
    private let apiClientProvider: () -> OBAAPIClient
    private let locationProvider: () -> CLLocation?
    private var searchTask: Task<Void, Never>?
    private let recentStopsKey = "watch_recent_search_stops"
    private let recentSearchTermsKey = "watch_recent_search_terms"
    private let bookmarksKey = "watch.bookmarks"

    init(apiClientProvider: @escaping () -> OBAAPIClient, locationProvider: @escaping () -> CLLocation?) {
        self.apiClientProvider = apiClientProvider
        self.locationProvider = locationProvider
        self.recentStops = Self.loadRecentStops(from: recentStopsKey)
        self.recentSearchTerms = WatchAppState.userDefaults.stringArray(forKey: recentSearchTermsKey) ?? []
        self.bookmarkResults = Self.loadBookmarks(from: bookmarksKey)
    }
    
    func performSearch() {
        searchTask?.cancel()
        
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            searchResults = []
            bookmarkResults = []
            return
        }
        
        // Save to recent search terms if not already there or move to top
        updateRecentSearchTerms(term: trimmed)
        
        searchTask = Task {
            await searchStops(query: trimmed)
            filterBookmarks(matching: trimmed)
        }
    }

    private func updateRecentSearchTerms(term: String) {
        var terms = recentSearchTerms
        terms.removeAll { $0.lowercased() == term.lowercased() }
        terms.insert(term, at: 0)
        if terms.count > 5 {
            terms = Array(terms.prefix(5))
        }
        recentSearchTerms = terms
        WatchAppState.userDefaults.set(terms, forKey: recentSearchTermsKey)
    }

    func selectRecentSearchTerm(_ term: String) {
        searchText = term
        performSearch()
    }

    func clearRecentSearchTerms() {
        recentSearchTerms = []
        WatchAppState.userDefaults.removeObject(forKey: recentSearchTermsKey)
    }

    func recordRecent(stop: OBAStop) {
        // Move stop to front and cap at 10 entries.
        recentStops.removeAll { $0.id == stop.id }
        recentStops.insert(stop, at: 0)
        if recentStops.count > 10 {
            recentStops = Array(recentStops.prefix(10))
        }

        // Persist to UserDefaults.
        do {
            let data = try JSONEncoder().encode(recentStops)
            WatchAppState.userDefaults.set(data, forKey: recentStopsKey)
        } catch {
            Logger.error("Failed to persist recent stops: \(error)")
        }
    }
    
    private func searchStops(query: String) async {
        let apiClient = apiClientProvider()
        isLoading = true
        errorMessage = nil
        
        defer { isLoading = false }
        
        var location = locationProvider()
        if location == nil {
            do {
                let agencies = try await apiClient.fetchAgenciesWithCoverage()
                if let first = agencies.first {
                    location = CLLocation(latitude: first.centerLatitude, longitude: first.centerLongitude)
                } else {
                    errorMessage = OBALoc("search.error.location_required", value: "Location required for search", comment: "Location required")
                    return
                }
            } catch {
                errorMessage = OBALoc("search.error.location_required", value: "Location required for search", comment: "Location required")
                return
            }
        }
        
        do {
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let loc = location else {
                errorMessage = OBALoc("search.error.location_required", value: "Location required for search", comment: "Location required")
                return
            }
            let fetched = try await apiClient.searchStops(
                query: trimmed,
                latitude: loc.coordinate.latitude,
                longitude: loc.coordinate.longitude,
                radius: 5000.0
            )

            searchResults = fetched.stops.sorted { (s1: OBAStop, s2: OBAStop) in
                let loc1 = CLLocation(latitude: s1.latitude, longitude: s1.longitude)
                let loc2 = CLLocation(latitude: s2.latitude, longitude: s2.longitude)
                let d1 = loc1.distance(from: loc)
                let d2 = loc2.distance(from: loc)
                return d1 < d2
            }
        } catch {
            errorMessage = error.watchOSUserFacingMessage
        }
    }

    private func filterBookmarks(matching query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let all = Self.loadBookmarks(from: bookmarksKey)
        guard !trimmed.isEmpty else {
            bookmarkResults = []
            return
        }
        bookmarkResults = all.filter { bm in
            if bm.name.localizedCaseInsensitiveContains(trimmed) { return true }
            if let route = bm.routeShortName, route.localizedCaseInsensitiveContains(trimmed) { return true }
            if let headsign = bm.tripHeadsign, headsign.localizedCaseInsensitiveContains(trimmed) { return true }
            if let stop = bm.stop {
                if stop.name.localizedCaseInsensitiveContains(trimmed) { return true }
                if let code = stop.code, code.localizedCaseInsensitiveContains(trimmed) { return true }
            }
            return false
        }
    }

    private static func loadRecentStops(from key: String) -> [OBAStop] {
        guard let data = WatchAppState.userDefaults.data(forKey: key) else { return [] }
        do {
            return try JSONDecoder().decode([OBAStop].self, from: data)
        } catch {
            Logger.error("Failed to decode recent stops: \(error)")
            return []
        }
    }

    private static func loadBookmarks(from key: String) -> [WatchBookmark] {
        guard let data = WatchAppState.userDefaults.data(forKey: key) else { return [] }
        do {
            return try JSONDecoder().decode([WatchBookmark].self, from: data)
        } catch {
            Logger.error("Failed to decode bookmarks: \(error)")
            return []
        }
    }
}
