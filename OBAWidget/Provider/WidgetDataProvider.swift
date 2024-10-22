//
//  WidgetDataProvider .swift
//  OBAWidget
//
//  Created by Manu on 2024-10-15.
//

import Foundation
import OBAKitCore
import CoreLocation


/// `WidgetDataProvider` is responsible for fetching and providing relevant data to the widget timeline provider.
@MainActor
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
        if bookmarks.count == 0 {
            bookmarks = app.userDataStore.bookmarks
        }
        return bookmarks
    }
    
    /// Loads arrivals and departures for all favorited bookmarks for widget efficiently.
    public func loadData() async {
        guard let apiService = app.apiService else {
            return
        }
        
        let bookmarks = getBookmarks().filter { $0.isTripBookmark }
        
        await withTaskGroup(of: Void.self) { group in
            for bookmark in bookmarks {
                group.addTask {
                    do {
                        let stopArrivals = try await apiService.getArrivalsAndDeparturesForStop(
                            id: bookmark.stopID,
                            minutesBefore: 0,
                            minutesAfter: 60
                        ).entry
                        
                        // Update the tripBookmarkKeys dictionary on the main thread
                        await MainActor.run {
                            let keysAndDeps = stopArrivals.arrivalsAndDepartures.tripKeyGroupedElements
                            for (key, deps) in keysAndDeps {
                                self.arrDepDic[key] = deps
                            }
                        }
                        
                    } catch {
                        print("Error Fetching data for bookmark \(bookmark.name): \(error)")
                    }
                }
            }
        }
    }
    
    public func lookupArrivalDeparture(with key: TripBookmarkKey) -> [ArrivalDeparture] {
        return arrDepDic[key, default: []]
    }
    
    public func getBookmarks() -> [Bookmark] {
        return bestAvailableBookmarks
    }
    
    private var arrDepDic = [TripBookmarkKey: [ArrivalDeparture]]()
    
}
