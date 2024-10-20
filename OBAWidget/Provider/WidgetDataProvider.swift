//
//  WidgetDataProvider .swift
//  OBAWidget
//
//  Created by Manu on 2024-10-15.
//

import Foundation
import OBAKitCore
import CoreLocation

public struct BookmarkDeparture: Hashable {
    let bookmark: Bookmark
    let departures: [ArrivalDeparture]
}

/// `WidgetDataProvider` is responsible for fetching and providing relevant data to the widget timeline provider.
class WidgetDataProvider: NSObject, ObservableObject {

    public let formatters = Formatters(
        locale: Locale.autoupdatingCurrent,
        calendar: Calendar.autoupdatingCurrent,
        themeColors: ThemeColors.shared
    )
    
    static let shared = WidgetDataProvider()
 
    //MARK: initializer
    override init(){
        super.init()
    }
    
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
        if bookmarks.count == 0 {
            bookmarks = app.userDataStore.bookmarks
        }
        return bookmarks
    }
    
    /// Loads arrivals and departures for all favorited bookmarks for widget efficiently.
    /// Returns an array of `BookmarkDepartures`.
    public func loadData() async -> [BookmarkDeparture] {
        guard let apiService = app.apiService else {
            return []
        }
        
        var bookmarkDepartures: [BookmarkDeparture] = []
        
        let bookmarks = bestAvailableBookmarks
        
        await withTaskGroup(of: BookmarkDeparture?.self) { group in
            for bookmark in bookmarks {
                group.addTask {
                    do {
                        let stopArrivals = try await apiService.getArrivalsAndDeparturesForStop(
                            id: bookmark.stopID,
                            minutesBefore: 0,
                            minutesAfter: 60
                        ).entry
                        
                        let departures = stopArrivals.arrivalsAndDepartures
                        
                        return BookmarkDeparture(
                            bookmark: bookmark,
                            departures: departures
                        )
                    }catch{
                        print("Error Fetching data for bookmark \(bookmark.name) : \(error)")
                        return nil
                    }
                }
            }
            
            for await result in group {
                if let data = result {
                    bookmarkDepartures.append(data)
                }
            }
        }
        return bookmarkDepartures
    }
}
