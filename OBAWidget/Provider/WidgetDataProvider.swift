//  WidgetDataProvider.swift
//  OBAWidget
//
//  Created by Manu on 2024-10-15.
//

import Foundation
import OBAKitCore
import CoreLocation

/// `WidgetDataProvider` is responsible for fetching and providing relevant data to the widget timeline provider.
class WidgetDataProvider: NSObject, ObservableObject {
    
    public let formatters = Formatters(
        locale: Locale.autoupdatingCurrent,
        calendar: Calendar.autoupdatingCurrent,
        themeColors: ThemeColors.shared
    )
    
    static let shared = WidgetDataProvider()
    private let userDefaults = UserDefaults(suiteName: Bundle.main.appGroup!)!
    
    private lazy var locationManager = CLLocationManager()
    private lazy var locationService = LocationService(
        userDefaults: userDefaults,
        locationManager: locationManager
    )
    
    private lazy var app: CoreApplication = {
        let bundledRegions = Bundle.main.path(forResource: "regions", ofType: "json")!
        let config = CoreAppConfig(appBundle: Bundle.main, userDefaults: userDefaults, bundledRegionsFilePath: bundledRegions)
        return CoreApplication(config: config)
    }()
    
    private var bestAvailableBookmarks: [Bookmark] {
        var bookmarks = app.userDataStore.favoritedBookmarks
        if bookmarks.isEmpty {
            bookmarks = app.userDataStore.bookmarks
        }
        return bookmarks
    }
    
    /// Loads arrivals and departures for all favorited bookmarks for the widget.
    public func loadData() async {
        guard let apiService = app.apiService else { return }
        
        let bookmarks = getBookmarks()
            .filter { $0.isTripBookmark && $0.regionIdentifier == app.regionsService.currentRegion?.id }
        
        for bookmark in bookmarks {
            await fetchArrivalData(for: bookmark, apiService: apiService)
        }
    }
    
    /// Fetch arrival data for a specific bookmark and update the dictionary.
    private func fetchArrivalData(for bookmark: Bookmark, apiService: RESTAPIService) async {
        do {
            let stopArrivals = try await apiService.getArrivalsAndDeparturesForStop(
                id: bookmark.stopID,
                minutesBefore: 0,
                minutesAfter: 60
            ).entry
            
            await MainActor.run {
                let keysAndDeps = stopArrivals.arrivalsAndDepartures.tripKeyGroupedElements
                for (key, deps) in keysAndDeps {
                    self.arrDepDic[key] = deps
                }
            }
        } catch {
            Logger.error("Error fetching data for bookmark \(bookmark.name): \(error)")
        }
    }
    
    /// Looks up arrival and departure data for a given trip key.
    public func lookupArrivalDeparture(with key: TripBookmarkKey) -> [ArrivalDeparture] {
        return arrDepDic[key, default: []]
    }
    
    /// Retrieves the best available bookmarks.
    public func getBookmarks() -> [Bookmark] {
        return bestAvailableBookmarks
    }
    
    /// Dictionary to store arrival and departure data grouped by trip keys.
    private var arrDepDic = [TripBookmarkKey: [ArrivalDeparture]]()
}
