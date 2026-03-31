//
//  RegionsService.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import CoreLocation

@objc(OBARegionsServiceDelegate)
public protocol RegionsServiceDelegate {
    @objc optional func regionsServiceUnableToSelectRegion(_ service: RegionsService)
    @objc optional func regionsService(_ service: RegionsService, updatedRegionsList regions: [Region])
    @objc optional func regionsService(_ service: RegionsService, willUpdateToRegion region: Region)
    @objc optional func regionsService(_ service: RegionsService, updatedRegion region: Region)
    @objc optional func regionsService(_ service: RegionsService, changedAutomaticRegionSelection value: Bool)

    /// This delegate method is called when the region list update is cancelled before retrieving data.
    ///
    /// The update will be cancelled when the regions list has been updated within the past week, and an update is not forced.
    /// - parameter service: The `RegionsService` object.
    @objc optional func regionsServiceListUpdateCancelled(_ service: RegionsService)

    @objc optional func regionsService(_ service: RegionsService, displayError error: Error)
}

/// Manages the app's list of `Region`s, including list updates, and which `Region` the user is currently located in.
public class RegionsService: NSObject, LocationServiceDelegate {
    private let apiService: RegionsAPIService?
    private let locationService: LocationService
    private let userDefaults: UserDefaults
    private let bundledRegionsFilePath: String
    private let apiPath: String?

    private let fileStorage: RegionsFileStorageProtocol
    private let fixedRegionName: String?
    private let fixedRegionOBABaseURL: URL?

    /// Initializes a `RegionsService` object, which coordinates the current region, downloading new data, and storage.
    /// - Parameters:
    ///   - apiService: Retrieves new data from the region server and turns it into models.
    ///   - locationService: A location service object.
    ///   - userDefaults: The user defaults object.
    ///   - bundledRegionsFilePath: The path to the bundled regions file. It is probably named "regions.json" or something similar.
    ///   - apiPath: The path to the remote regions.json file on the server. e.g. /path/to/regions.json
    ///   - fileStorage: The file-based storage implementation. Defaults to `RegionsFileStorage`.
    ///   - delegate: A delegate object for callbacks.
    ///   - fixedRegionName: A region name from `OBAKitConfig` to auto-select, bypassing the region picker.
    ///   - fixedRegionOBABaseURL: A fallback OBA base URL used when `fixedRegionName` doesn't match any known region.
    public init(apiService: RegionsAPIService?, locationService: LocationService, userDefaults: UserDefaults, fileStorage: RegionsFileStorageProtocol = RegionsFileStorage(), bundledRegionsFilePath: String, apiPath: String?, delegate: RegionsServiceDelegate? = nil, fixedRegionName: String? = nil, fixedRegionOBABaseURL: URL? = nil) {
        self.apiService = apiService
        self.locationService = locationService
        self.userDefaults = userDefaults
        self.bundledRegionsFilePath = bundledRegionsFilePath
        self.apiPath = apiPath
        self.fileStorage = fileStorage

        self.fixedRegionName = fixedRegionName
        self.fixedRegionOBABaseURL = fixedRegionOBABaseURL

        self.userDefaults.register(defaults: [
            RegionsService.automaticallySelectRegionUserDefaultsKey: true,
            RegionsService.alwaysRefreshRegionsOnLaunchUserDefaultsKey: false
        ])

        // One-time migration from UserDefaults to disk-based storage.
        RegionsService.migrateFromUserDefaultsIfNeeded(userDefaults: userDefaults, fileStorage: fileStorage)

        if let regions = RegionsService.loadStoredRegions(from: fileStorage), regions.count > 0 {
            self.regions = regions
        }
        else {
            self.regions = RegionsService.bundledRegions(path: bundledRegionsFilePath)
        }

        super.init()

        if let delegate = delegate {
            addDelegate(delegate)
        }

        let autoSelectRegion = userDefaults.bool(forKey: RegionsService.automaticallySelectRegionUserDefaultsKey) || currentRegion == nil

        if autoSelectRegion, let location = locationService.currentLocation {
            currentRegion = RegionsService.firstRegion(in: self.regions, containing: location)
        }

        // Fixed region from OBAKitConfig: match by name, then fall back to URL.
        // See: https://github.com/OneBusAway/onebusaway-ios/issues/608
        if currentRegion == nil, let fixedName = fixedRegionName {
            let match = self.regions.first(where: { $0.name == fixedName })
                ?? self.regions.first(where: { fixedRegionOBABaseURL != nil && $0.OBABaseURL == fixedRegionOBABaseURL })

            if let match {
                currentRegion = match
                userDefaults.set(false, forKey: RegionsService.automaticallySelectRegionUserDefaultsKey)
            } else {
                Logger.error("Fixed region '\(fixedName)' not found in bundled or stored regions")
            }
        }

        // Auto-select when only one active region is available.
        if currentRegion == nil {
            let activeRegions = self.regions.filter { $0.isActive }
            if activeRegions.count == 1, let onlyRegion = activeRegions.first {
                currentRegion = onlyRegion
            }
        }

        self.locationService.addDelegate(self)
    }

    // MARK: - Delegates

    private let delegates = NSHashTable<RegionsServiceDelegate>.weakObjects()

    public func addDelegate(_ delegate: RegionsServiceDelegate) {
        delegates.add(delegate)
    }

    public func removeDelegate(_ delegate: RegionsServiceDelegate) {
        delegates.remove(delegate)
    }

    private func notifyDelegatesRegionChanged(_ region: Region) {
        for delegate in delegates.allObjects {
            delegate.regionsService?(self, willUpdateToRegion: region)
        }

        for delegate in delegates.allObjects {
            delegate.regionsService?(self, updatedRegion: region)
        }
    }

    private func notifyDelegatesRegionsListUpdated() {
        for delegate in delegates.allObjects {
            delegate.regionsService?(self, updatedRegionsList: regions)
        }
    }

    private func notifyDelegatesUnableToSelectRegion() {
        for delegate in delegates.allObjects {
            delegate.regionsServiceUnableToSelectRegion?(self)
        }
    }

    private func notifyDelegatesRegionListUpdateCancelled() {
        for delegate in delegates.allObjects {
            delegate.regionsServiceListUpdateCancelled?(self)
        }
    }

    private func notifyDelegatesAutomaticallySelectRegionChanged(value: Bool) {
        for delegate in delegates.allObjects {
            delegate.regionsService?(self, changedAutomaticRegionSelection: value)
        }
    }

    private func notifyDelegatesDisplayError(_ error: Error) {
        for delegate in delegates.allObjects {
            delegate.regionsService?(self, displayError: error)
        }
    }

    // MARK: - Regions Data

    public private(set) var regions: [Region] {
        didSet {
            if regions.count > 0 {
                storeRegions()
                notifyDelegatesRegionsListUpdated()
                updateCurrentRegionFromLocation()
            }
        }
    }

    /// The app's currently-selected `Region`.
    ///
    /// The region identifier is persisted in `UserDefaults`. On read, the full `Region` is
    /// looked up by identifier so that stale object data is never stored on disk.
    public var currentRegion: Region? {
        get {
            guard let identifier = userDefaults.object(forKey: RegionsService.currentRegionIdentifierUserDefaultsKey) as? Int else {
                return nil
            }
            return find(id: identifier)
        }
        set {
            guard let newValue else { return }

            let storedIdentifier = userDefaults.object(forKey: RegionsService.currentRegionIdentifierUserDefaultsKey) as? Int
            guard newValue.regionIdentifier != storedIdentifier else { return }

            userDefaults.set(newValue.regionIdentifier, forKey: RegionsService.currentRegionIdentifierUserDefaultsKey)
            notifyDelegatesRegionChanged(newValue)
        }
    }

    /// The `Region`, if one exists, that the user is physically located in. Note that this may be different from `currentRegion`.
    public var physicallyLocatedRegion: Region? {
        guard let location = locationService.currentLocation else {
            return nil
        }

        return RegionsService.firstRegion(in: regions, containing: location)
    }

    public var automaticallySelectRegion: Bool {
        get {
            userDefaults.bool(forKey: RegionsService.automaticallySelectRegionUserDefaultsKey)
        }
        set {
            userDefaults.set(newValue, forKey: RegionsService.automaticallySelectRegionUserDefaultsKey)
            if newValue {
                // When this value toggles to true, we should refresh the current region.
                updateCurrentRegionFromLocation()
            }
            notifyDelegatesAutomaticallySelectRegionChanged(value: newValue)
        }
    }

    public func find(id: Int) -> Region? {
        if let region = regions.first(where: { $0.regionIdentifier == id }) {
            return region
        }
        else {
            return customRegions.first { $0.regionIdentifier == id }
        }
    }

    // MARK: - Custom Regions

    /// Adds the provided custom region to the RegionsService.
    /// If an existing custom region with the same `regionIdentifier` exists, the new region replaces the existing region.
    /// - throws: Persistence storage errors.
    public func add(customRegion newRegion: Region) async throws {
        try fileStorage.saveCustomRegion(newRegion)
    }

    /// Deletes the custom region. If the region could not be found, this method exits normally.
    /// - parameter customRegion: The custom region to delete.
    /// - throws: If `customRegion` is the currently selected region, this method will throw.
    public func delete(customRegion: Region) async throws {
        try await delete(customRegionIdentifier: customRegion.regionIdentifier)
    }

    /// Deletes the custom region with the matching identifier. If a region with the given identifier could not be found, this method exits normally.
    /// - parameter identifier: The region identifier used to find the custom region to delete.
    /// - throws: If the custom region cannot be deleted.
    public func delete(customRegionIdentifier identifier: RegionIdentifier) async throws {
        guard self.currentRegion?.regionIdentifier != identifier else {
            throw UnstructuredError(
                "Cannot delete the current selected region",
                recoverySuggestion: "Choose a different region to be the currently selected region, before deleting this region.")
        }

        try fileStorage.deleteCustomRegion(identifier: identifier)
    }

    public var customRegions: [Region] {
        fileStorage.loadCustomRegions()
    }

    public var allRegions: [Region] {
        return regions + customRegions
    }

    // MARK: - Region Data Storage — UserDefaults Keys

    public static let alwaysRefreshRegionsOnLaunchUserDefaultsKey = "OBAAlwaysRefreshRegionsOnLaunchUserDefaultsKey"
    static let automaticallySelectRegionUserDefaultsKey = "OBAAutomaticallySelectRegionUserDefaultsKey"
    static let currentRegionIdentifierUserDefaultsKey = "OBACurrentRegionIdentifierUserDefaultsKey"
    static let regionsUpdatedAtUserDefaultsKey = "OBARegionsUpdatedAtUserDefaultsKey"

    // Legacy keys — kept only for the one-time migration read; not written after migration.
    static let legacyStoredRegionsUserDefaultsKey = "OBAStoredRegionsUserDefaultsKey"
    static let legacyStoredCustomRegionsUserDefaultsKey = "OBAStoredCustomRegionsUserDefaultsKey"
    static let legacyCurrentRegionUserDefaultsKey = "OBACurrentRegionUserDefaultsKey"

    // MARK: - Save Regions

    private func storeRegions() {
        do {
            try fileStorage.saveDefaultRegions(regions)
            userDefaults.set(Date(), forKey: RegionsService.regionsUpdatedAtUserDefaultsKey)
        }
        catch {
            Logger.error("RegionsService: Unable to write regions to disk: \(error)")
        }
    }

    // MARK: - Load Stored Regions

    private class func loadStoredRegions(from fileStorage: RegionsFileStorageProtocol) -> [Region]? {
        do {
            let regions = try fileStorage.loadDefaultRegions()
            if let regions = regions, !regions.isEmpty {
                return regions
            }
            return nil
        } catch {
            Logger.error("RegionsService: Unable to load regions from disk: \(error)")
            return nil
        }
    }

    // MARK: - UserDefaults → Disk Migration

    /// Performs a one-time migration of region data from the legacy UserDefaults
    /// storage format to the new disk-based storage format.
    ///
    /// After migrating, the legacy UserDefaults keys are removed so this runs only once.
    private static func migrateFromUserDefaultsIfNeeded(userDefaults: UserDefaults, fileStorage: RegionsFileStorageProtocol) {
        // Migrate downloaded/server regions
        if let data = userDefaults.data(forKey: legacyStoredRegionsUserDefaultsKey) {
            if let regions = try? PropertyListDecoder().decode([Region].self, from: data), !regions.isEmpty {
                do {
                    try fileStorage.saveDefaultRegions(regions)
                    Logger.info("RegionsService: Migrated \(regions.count) regions from UserDefaults to disk.")
                } catch {
                    Logger.error("RegionsService: Migration failed for default regions: \(error)")
                }
            }
            userDefaults.removeObject(forKey: legacyStoredRegionsUserDefaultsKey)
        }

        // Migrate custom regions
        if let data = userDefaults.data(forKey: legacyStoredCustomRegionsUserDefaultsKey) {
            if let customRegions = try? PropertyListDecoder().decode([Region].self, from: data) {
                for region in customRegions {
                    do {
                        try fileStorage.saveCustomRegion(region)
                    } catch {
                        Logger.error("RegionsService: Migration failed for custom region '\(region.name)': \(error)")
                    }
                }
                if !customRegions.isEmpty {
                    Logger.info("RegionsService: Migrated \(customRegions.count) custom regions from UserDefaults to disk.")
                }
            }
            userDefaults.removeObject(forKey: legacyStoredCustomRegionsUserDefaultsKey)
        }

        // Migrate currentRegion → store only the identifier
        if let data = userDefaults.data(forKey: legacyCurrentRegionUserDefaultsKey) {
            if let region = try? PropertyListDecoder().decode(Region.self, from: data) {
                userDefaults.set(region.regionIdentifier, forKey: currentRegionIdentifierUserDefaultsKey)
            }
            userDefaults.removeObject(forKey: legacyCurrentRegionUserDefaultsKey)
        }
    }

    // MARK: - Bundled Regions

    // swiftlint:disable force_try

    private static func bundledRegions(path: String) -> [Region] {
        let data = try! NSData(contentsOfFile: path) as Data
        let response = try! JSONDecoder.RESTDecoder().decode(RESTAPIResponse<[Region]>.self, from: data)
        return response.list
    }

    // swiftlint:enable force_try

    // MARK: - Update Helpers

    /// Returns `true` if the list of `Region`s should be updated from the server.
    ///
    /// By default, this method only returns `true` if it has been at least a day since the last successful refresh,
    /// however you can override this to force it to update the list of `Region`s on every launch if you set the
    /// `UserDefaults` key `RegionsService.alwaysRefreshRegionsOnLaunchUserDefaultsKey` to `true`.
    /// You can set this value to `true` either through some console trickery, or by toggling the setting in the Settings controller
    /// when Debug Mode is enabled in the `MoreViewController`.
    var shouldUpdateRegionList: Bool {
        if userDefaults.bool(forKey: RegionsService.alwaysRefreshRegionsOnLaunchUserDefaultsKey) {
            return true
        }

        guard let lastUpdatedAt = userDefaults.object(forKey: RegionsService.regionsUpdatedAtUserDefaultsKey) as? Date else {
            return true
        }

        // True if it has been at least the number of seconds in a day since the last update.
        return abs(lastUpdatedAt.timeIntervalSinceNow) >= 86400
    }

    // MARK: - Public Methods

    /// Fetches the current list of `Region`s from the network.
    public func refreshRegions() async throws {
        guard let apiService, let apiPath else {
            return
        }

        let regions = try await apiService.getRegions(apiPath: apiPath).list
        guard !regions.isEmpty else {
            return
        }

        self.regions = regions
    }

    /// Fetches the current list of `Region`s from the network.
    /// - Parameter forceUpdate: Forces an update of the regions list, even if the last update happened less than one week ago.
    public func updateRegionsList(forceUpdate: Bool = false) async {
        // only update once per week, unless forceUpdate is true.
        if !shouldUpdateRegionList && !forceUpdate {
            notifyDelegatesRegionListUpdateCancelled()
            return
        }

        do {
            try await refreshRegions()
            updateCurrentRegionFromLocation()
        } catch {
            notifyDelegatesDisplayError(error)
        }
    }

    // MARK: - LocationServiceDelegate

    public func locationService(_ service: LocationService, locationChanged location: CLLocation) {
        updateCurrentRegionFromLocation()
    }

    private class func firstRegion(in regions: [Region], containing location: CLLocation) -> Region? {
        return (regions.filter { $0.contains(location: location) }).first
    }

    /// Refreshes the `currentRegion` based upon the user's current location.
    /// - Note: If `locationService.currentLocation` returns `nil`, then this method will do nothing.
    public func updateCurrentRegionFromLocation() {
        // We can't do anything here if we can't get the user's current location.
        // Also, don't set the user's region if they've specifically told us not to.
        guard
            locationService.currentLocation != nil,
            automaticallySelectRegion
        else {
            return
        }

        // Prompt the user if their current location doesn't match a region.
        guard let newRegion = physicallyLocatedRegion else {
            notifyDelegatesUnableToSelectRegion()
            return
        }

        currentRegion = newRegion
    }
}
