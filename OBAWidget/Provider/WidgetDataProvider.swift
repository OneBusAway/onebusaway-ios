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
    static let shared = WidgetDataProvider()

    private let userDefaults = UserDefaults(suiteName: Bundle.main.appGroup!)!
    private lazy var locationManager = CLLocationManager()
    private lazy var locationService = LocationService(
        userDefaults: userDefaults,
        locationManager: locationManager
    )

    private lazy var app: CoreApplication = {
        let config = CoreAppConfig(
            appBundle: Bundle.main,
            userDefaults: userDefaults,
            bundledRegionsFilePath: Bundle.main.path(forResource: "regions", ofType: "json")!
        )
        return CoreApplication(config: config)
    }()

    private var bestAvailableBookmarks: [Bookmark] {
        var bookmarks = app.userDataStore.favoritedBookmarks
        if bookmarks.isEmpty {
            bookmarks = app.userDataStore.bookmarks
        }
        return bookmarks
    }

    /// Dictionary mapping trip bookmark keys to arrival/departure data.
    private var arrDepDic = [TripBookmarkKey: [ArrivalDeparture]]()

    /// Formatters for localization and styling.
    let formatters = Formatters(
        locale: Locale.autoupdatingCurrent,
        calendar: Calendar.autoupdatingCurrent,
        themeColors: ThemeColors.shared
    )

    /// Loads arrivals and departures for all favorited bookmarks for the widget.
    func loadData() async {
        arrDepDic = [:] 

        guard let apiService = app.getNewRefreshedRESTAPIService() else {
            Logger.error("Failed to get REST API Service.")
            return
        }

        let bookmarks = getBookmarks()
        guard !bookmarks.isEmpty else {
            Logger.info("No bookmarks found to load data.")
            return
        }

        await withTaskGroup(of: Void.self) { group in
            bookmarks.forEach { bookmark in
                group.addTask { [weak self] in
                    await self?.fetchArrivalData(for: bookmark, apiService: apiService)
                }
            }
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
                stopArrivals.arrivalsAndDepartures.tripKeyGroupedElements.forEach { key, deps in
                    arrDepDic[key] = deps
                }
            }
        } catch {
            Logger.error("""
            Error fetching data for bookmark: '\(bookmark.name)' 
            (ID: \(bookmark.id)). Error: \(error.localizedDescription)
            """)
        }
    }

    /// Looks up arrival and departure data for a given trip key.
    func lookupArrivalDeparture(with key: TripBookmarkKey) -> [ArrivalDeparture] {
        arrDepDic[key, default: []]
    }

    /// Gets bookmarks of the selected region.
    public func getBookmarks() -> [Bookmark] {
        return bestAvailableBookmarks.filter { $0.isTripBookmark && $0.regionIdentifier == app.regionsService.currentRegion?.id }
    }
}
