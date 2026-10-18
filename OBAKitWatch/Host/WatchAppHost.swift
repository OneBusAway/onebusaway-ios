//
//  WatchAppHost.swift
//  OBAKitWatch
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import CoreLocation
import Observation
import OBAKitCore

/// The watch app's service graph. Built once by the `@main` struct and passed
/// down with `.environment(host)`; screens read `@Environment(WatchAppHost.self)`.
///
/// Deliberately not a `CoreApplication`: that initializer starts a regions
/// fetch, builds Obaco and survey services, opens and purges the GRDB stop
/// cache, and bumps the launch counter that survey gating reads. The watch
/// needs none of it. Never read `\.coreApplication` from watch code — its
/// default value builds one.
@MainActor
@Observable
public final class WatchAppHost: NSObject, LocationServiceDelegate, RegionsServiceDelegate {
    public let locationService: LocationService
    public let regionsService: RegionsService
    public let formatters: Formatters
    public let bookmarkStore: WatchBookmarkStore

    /// Follows `regionsService.currentRegion`; nil until a region is known.
    public var apiService: RESTAPIService? { apiServiceProvider.apiService }

    /// Mirrors `regionsService.currentRegion` so views can react to region changes.
    public private(set) var currentRegion: Region?

    /// Mirrors `locationService.authorizationStatus` so views can react to a grant.
    public private(set) var authorizationStatus: CLAuthorizationStatus

    /// Cached bookmarks received from the companion iPhone app.
    public var bookmarks: [WatchBookmark] { bookmarkStore.bookmarks }

    /// Cached bookmark groups received from the companion iPhone app.
    public var bookmarkGroups: [WatchBookmarkGroup] { bookmarkStore.groups }

    // `RegionsService` holds its delegates weakly; the host retains both.
    @ObservationIgnored private let apiServiceProvider: StandaloneAPIServiceProvider
    @ObservationIgnored private let resolvedRegionPersister: ResolvedRegionPersister
    @ObservationIgnored private let userDefaults: UserDefaults
    @ObservationIgnored private var isRegionFromSync: Bool
    @ObservationIgnored private var isApplyingSyncedRegion = false
    @ObservationIgnored private var syncObserverTask: Task<Void, Never>?

    private static let isRegionFromSyncUserDefaultsKey = "WatchAppHost.isRegionFromSync"

    public init(
        userDefaults: UserDefaults,
        locationService: LocationService,
        bundledRegionsFilePath: String,
        regionsServerBaseURL: URL?,
        regionsAPIPath: String?,
        apiKey: String,
        appVersion: String,
        dataLoader: URLDataLoader = URLSession.shared
    ) {
        self.locationService = locationService
        self.formatters = Formatters(locale: .current, calendar: .current, themeColors: .shared)

        // The watch has its own client identity, shared with its widget through
        // the app-group suite. The phone's UUID is never synced.
        let uuid = UserUUID.value(in: userDefaults)

        let regionsAPIService = regionsServerBaseURL.map {
            RegionsAPIService.standalone(baseURL: $0, apiKey: apiKey, appVersion: appVersion, uuid: uuid, dataLoader: dataLoader)
        }
        let regionsService = RegionsService(
            apiService: regionsAPIService,
            locationService: locationService,
            userDefaults: userDefaults,
            bundledRegionsFilePath: bundledRegionsFilePath,
            apiPath: regionsAPIPath
        )
        self.regionsService = regionsService

        let provider = StandaloneAPIServiceProvider(
            regionsService: regionsService,
            apiKey: apiKey,
            appVersion: appVersion,
            uuid: uuid,
            dataLoader: dataLoader
        )
        self.apiServiceProvider = provider

        // The step 6 watch widget reads the resolved region from the suite.
        self.resolvedRegionPersister = ResolvedRegionPersister(
            regionsService: regionsService,
            store: ResolvedRegionStore(userDefaults: userDefaults)
        )

        let bookmarkStore = WatchBookmarkStore(userDefaults: userDefaults)
        self.bookmarkStore = bookmarkStore
        self.userDefaults = userDefaults
        self.isRegionFromSync = userDefaults.bool(forKey: Self.isRegionFromSyncUserDefaultsKey)

        self.currentRegion = regionsService.currentRegion
        self.authorizationStatus = locationService.authorizationStatus

        super.init()

        locationService.addDelegate(self)
        regionsService.addDelegate(self)

        startWatchSessionSync()
    }

    /// Applies the latest payload synced from the phone, then follows later ones.
    private func startWatchSessionSync() {
        WatchSessionBridge.shared.activate()

        if let latest = WatchSessionBridge.shared.latestReceivedPayload {
            bookmarkStore.update(payload: latest)
            if regionsService.currentRegion == nil || isRegionFromSync, let region = latest.region {
                applySyncedRegion(region)
            }
        }

        if regionsService.currentRegion == nil, let region = bookmarkStore.syncedRegion {
            applySyncedRegion(region)
        }

        self.syncObserverTask = Task { @MainActor [weak self] in
            for await payload in WatchSessionBridge.shared.payloads {
                guard let self else { break }
                self.bookmarkStore.update(payload: payload)
                if let syncedRegion = payload.region, self.regionsService.currentRegion == nil || self.isRegionFromSync {
                    self.applySyncedRegion(syncedRegion)
                }
            }
        }
    }

    private func applySyncedRegion(_ region: Region) {
        isApplyingSyncedRegion = true
        regionsService.currentRegion = region
        currentRegion = region
        isRegionFromSync = true
        userDefaults.set(true, forKey: Self.isRegionFromSyncUserDefaultsKey)
        isApplyingSyncedRegion = false
    }

    /// Builds the host from `Bundle.main`'s `OBAKitConfig`, the way an app's
    /// `watch.yml` configures it.
    public static func fromMainBundle() -> WatchAppHost {
        let bundle = Bundle.main
        guard
            let appGroup = bundle.appGroup,
            let userDefaults = UserDefaults(suiteName: appGroup),
            let bundledRegionsFilePath = bundle.bundledRegionsFilePath,
            let apiKey = bundle.restServerAPIKey
        else {
            fatalError("The watch app's Info.plist needs an OBAKitConfig dictionary with AppGroup, BundledRegionsFileName, and RESTServerAPIKey; see Apps/<App>/watch.yml.")
        }

        let locationService = LocationService(
            userDefaults: userDefaults,
            locationManager: CLLocationManager(),
            startsUpdatesOnAuthorization: false
        )

        return WatchAppHost(
            userDefaults: userDefaults,
            locationService: locationService,
            bundledRegionsFilePath: bundledRegionsFilePath,
            regionsServerBaseURL: bundle.regionsServerBaseAddress,
            regionsAPIPath: bundle.regionsServerAPIPath,
            apiKey: apiKey,
            appVersion: bundle.appVersion
        )
    }

    /// Once per launch. `RegionsService` gates it to once a day on its own.
    public func refreshRegionsList() {
        Task { await regionsService.updateRegionsList() }
    }

    // MARK: - LocationServiceDelegate

    public func locationService(_ service: LocationService, authorizationStatusChanged status: CLAuthorizationStatus) {
        authorizationStatus = status
    }

    // MARK: - RegionsServiceDelegate

    public func regionsService(_ service: RegionsService, updatedRegion region: Region) {
        currentRegion = region
        if !isApplyingSyncedRegion {
            isRegionFromSync = false
            userDefaults.set(false, forKey: Self.isRegionFromSyncUserDefaultsKey)
        }
    }

    public func regionsServiceUnableToSelectRegion(_ service: RegionsService) {
        currentRegion = nil
        if !isApplyingSyncedRegion {
            isRegionFromSync = false
            userDefaults.set(false, forKey: Self.isRegionFromSyncUserDefaultsKey)
        }
        if let region = bookmarkStore.syncedRegion {
            applySyncedRegion(region)
        }
    }
}
