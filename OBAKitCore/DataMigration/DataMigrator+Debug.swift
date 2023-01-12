//
//  DataMigrator+Debug.swift
//  OBAKitCore
//
//  Created by Alan Chu on 1/4/23.
//

import Foundation

extension DataMigrator {
    /// Loads an arbitrary exported UserDefaults file to a new instance of DataMigrator.
    public static nonisolated func createMigrator(fromUserDefaultsData data: Data) throws -> Self {
        let suiteName = "DataMigrator_\(Date().ISO8601Format())"
        guard let userDefaults = UserDefaults(suiteName: suiteName) else {
            throw UnstructuredError("Unable to create UserDefaults with the name \(suiteName)")
        }
        userDefaults.removePersistentDomain(forName: suiteName)      // Don't persist.

        guard let migrationPrefs: [String: Any] = try Dictionary(plistData: data) else {
            throw UnstructuredError("The provided dictionary is not of type [String: Any] or is empty.")
        }

        for (key, value) in migrationPrefs {
            userDefaults.set(value, forKey: key)
        }

        return self.init(userDefaults: userDefaults)
    }
}
