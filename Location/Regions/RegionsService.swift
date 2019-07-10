//
//  RegionsService.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 11/10/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import Foundation
import CoreLocation
import CocoaLumberjackSwift

@objc(OBARegionsServiceDelegate)
public protocol RegionsServiceDelegate: NSObjectProtocol {
    @objc optional func regionsServiceUnableToSelectRegion(_ service: RegionsService)
    @objc optional func regionsService(_ service: RegionsService, updatedRegion region: Region)
}

public class RegionsService: NSObject, LocationServiceDelegate {
    private let modelService: RegionsModelService
    private let locationService: LocationService
    private let userDefaults: UserDefaults

    public init(modelService: RegionsModelService, locationService: LocationService, userDefaults: UserDefaults) {
        self.modelService = modelService
        self.locationService = locationService
        self.userDefaults = userDefaults

        self.userDefaults.register(defaults: [
            RegionsService.automaticallySelectRegionUserDefaultsKey: true
        ])

        if let regions = RegionsService.loadStoredRegions(from: userDefaults), regions.count > 0 {
            self.regions = regions
        }
        else {
            self.regions = RegionsService.bundledRegions
        }

        super.init()

        if self.currentRegion == nil,
            userDefaults.bool(forKey: RegionsService.automaticallySelectRegionUserDefaultsKey),
            let location = locationService.currentLocation {
            currentRegion = RegionsService.firstRegion(in: self.regions, containing: location)
        }

        updateRegionsList()

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
            delegate.regionsService?(self, updatedRegion: region)
        }
    }

    private func notifyDelegatesUnableToSelectRegion() {
        for delegate in delegates.allObjects {
            delegate.regionsServiceUnableToSelectRegion?(self)
        }
    }

    // MARK: - Regions Data

    public private(set) var regions: [Region] {
        didSet {
            storeRegions()
            updateCurrentRegionFromLocation()
        }
    }

    public var currentRegion: Region? {
        get {
            do {
                return try userDefaults.decodeUserDefaultsObjects(type: Region.self, key: RegionsService.currentRegionUserDefaultsKey)
            }
            catch let error {
                DDLogError("Unable to read region from user defaults: \(error)")
                return nil
            }
        }
        set {
            guard let newValue = newValue else {
                return
            }

            do {
                try userDefaults.encodeUserDefaultsObjects(newValue, key: RegionsService.currentRegionUserDefaultsKey)
                notifyDelegatesRegionChanged(newValue)
            }
            catch {
                DDLogError("Unable to write currentRegion to user defaults: \(error)")
            }
        }
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
        }
    }

    public func find(id: Int) -> Region? {
        regions.first { $0.regionIdentifier == id }
    }

    // MARK: - Region Data Storage

    private static let automaticallySelectRegionUserDefaultsKey = "OBAAutomaticallySelectRegionUserDefaultsKey"
    static let storedRegionsUserDefaultsKey = "OBAStoredRegionsUserDefaultsKey"
    private static let currentRegionUserDefaultsKey = "OBACurrentRegionUserDefaultsKey"
    private static let regionsUpdatedAtUserDefaultsKey = "OBARegionsUpdatedAtUserDefaultsKey"

    // MARK: - Save Regions

    private func storeRegions() {
        do {
            try userDefaults.encodeUserDefaultsObjects(regions, key: RegionsService.storedRegionsUserDefaultsKey)
            userDefaults.set(Date(), forKey: RegionsService.regionsUpdatedAtUserDefaultsKey)
        }
        catch {
            DDLogError("Unable to write regions to user defaults: \(error)")
        }
    }

    // MARK: - Load Stored Regions

    private class func loadStoredRegions(from userDefaults: UserDefaults) -> [Region]? {
        guard
            let regions = try? userDefaults.decodeUserDefaultsObjects(type: [Region].self, key: RegionsService.storedRegionsUserDefaultsKey),
            regions.count > 0
        else {
            return nil
        }

        return regions
    }

    private class func loadCurrentRegion(from userDefaults: UserDefaults) -> Region? {
        do {
            return try userDefaults.decodeUserDefaultsObjects(type: Region.self, key: RegionsService.currentRegionUserDefaultsKey)
        }
        catch let error {
            DDLogError("Unable to decode current region data: \(error)")
            return nil
        }
    }

    // MARK: - Bundled Regions

    private class var bundledRegions: [Region] {
        let bundledRegionsFilePath = Bundle(for: self).path(forResource: "regions-v3", ofType: "json")!
        let data = try! NSData(contentsOfFile: bundledRegionsFilePath) as Data // swiftlint:disable:this force_try
        return DictionaryDecoder.decodeRegionsFileData(data)
    }

    // MARK: - Public Methods

    public func updateRegionsList(forceUpdate: Bool = false) {
        // only update once per week, unless forceUpdate is true.
        if let lastUpdatedAt = userDefaults.object(forKey: RegionsService.regionsUpdatedAtUserDefaultsKey) as? Date,
           abs(lastUpdatedAt.timeIntervalSinceNow) < 604800,
           !forceUpdate {
            return
        }

        let op = modelService.getRegions()
        op.then { [weak self] in
            guard let self = self else {
                return
            }

            self.regions = op.regions
            self.updateCurrentRegionFromLocation()
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
    private func updateCurrentRegionFromLocation() {
        guard let location = locationService.currentLocation else {
            return
        }

        guard let newRegion = RegionsService.firstRegion(in: regions, containing: location) else {
            notifyDelegatesUnableToSelectRegion()
            return
        }

        currentRegion = newRegion
    }
}
