//
//  MigrationDataExtractor.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 5/10/20.
//

import Foundation

/// Extracts data from the user defaults of 'classic' versions of OneBusAway for transition to the new application architecture.
public class MigrationDataExtractor: NSObject {
    /// Creates a new MigrationDataExtractor.
    /// - Parameter defaults: The UserDefaults object from which data will be migrated, if available.
    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    // MARK: - User Defaults

    private let defaults: UserDefaults

    private struct OldUserDefaultsKeys {
        static let bookmarks = "bookmarks"
        static let bookmarkGroups = "bookmarkGroups"
        static let currentRegion = "oBARegion"
        static let recentStops = "mostRecentStops"
        static let userID = "OBAApplicationUserId"
    }

    // MARK: - Data Extraction/Unarchiving

    /// Returns true if data exists to be migrated.
    var hasDataToMigrate: Bool {
        oldUserID != nil
    }

    var oldUserID: String? {
        defaults.string(forKey: OldUserDefaultsKeys.userID)
    }

    func extractBookmarkGroups() -> [MigrationBookmarkGroup]? {
        extractData(type: [MigrationBookmarkGroup].self, key: OldUserDefaultsKeys.bookmarkGroups)
    }

    func extractBookmarks() -> [MigrationBookmark]? {
        extractData(type: [MigrationBookmark].self, key: OldUserDefaultsKeys.bookmarks)
    }

    func extractRecentStops() -> [MigrationRecentStop]? {
        extractData(type: [MigrationRecentStop].self, key: OldUserDefaultsKeys.recentStops)
    }

    func extractRegion() -> MigrationRegion? {
        extractData(type: MigrationRegion.self, key: OldUserDefaultsKeys.currentRegion)
    }

    private func extractData<T>(type: T.Type, key: String) -> T? {
        guard
            let data = defaults.data(forKey: key),
            let unarchiver = buildUnarchiver(data: data)
        else {
            return nil
        }

        return unarchiver.decodeObject(forKey: key) as? T
    }

    private func buildUnarchiver(data: Data) -> NSKeyedUnarchiver? {
        do {
            let unarchiver = try NSKeyedUnarchiver(forReadingFrom: data)
            unarchiver.setClass(MigrationBookmarkGroup.self, forClassName: "OBABookmarkGroup")
            unarchiver.setClass(MigrationBookmark.self, forClassName: "OBABookmarkV2")
            unarchiver.setClass(MigrationRecentStop.self, forClassName: "OBAStopAccessEventV2")
            unarchiver.setClass(MigrationRegion.self, forClassName: "OBARegionV2")
            unarchiver.requiresSecureCoding = false
            return unarchiver
        } catch let error {
            Logger.error("Failed to create unarchiver with error: \(error)")
            return nil
        }
    }

    // MARK: - Miscellaneous

    /// Copies user defaults for the specified app group identifier to the main app's Documents directory, so it can be extracted via Xcode.
    ///
    /// This is useful for testing the data migration feature. To retrieve app group-sequestered user defaults, follow these steps in Xcode:
    /// 1. Run this method from the LLDB console.
    /// 2. Go to Window > Devices and Simulators.
    /// 3. Choose Devices and select your test device from the source list on the left.
    /// 4. Select OneBusAway (or your white label variant) from the list of Installed Apps.
    /// 5. Click on the 'gear' button and then "Download Container"
    /// 6. Locate the downloaded package in the Finder, right-click on it, and choose Show Package Contents.
    /// 7. Navigate to the Documents folder.
    /// 8. Data will be located in `defaults.plist`.
    ///
    /// - Parameter identifier: An app group identifier, e.g. `group.org.onebusaway.iphone`.
    ///
    /// - Note: If the Info.plist `OBAKitConfig` dictionary is properly configured, your app group can be accessed via the
    ///         property `Bundle.main.appGroup`.
    func copyAppGroupUserDefaultsToDocuments(appGroupIdentifier identifier: String) throws {
        let manager = FileManager()
        let appGroupURL = manager.containerURL(forSecurityApplicationGroupIdentifier: identifier)!
        let plistURL = appGroupURL.appendingPathComponent("Library/Preferences/\(identifier).plist")

        let destinationURL = manager.urls(for: .documentDirectory, in: .userDomainMask).last!.appendingPathComponent("defaults.plist")
        try manager.copyItem(at: plistURL, to: destinationURL)
    }
}
