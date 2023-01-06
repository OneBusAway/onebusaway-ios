//
//  DataMigrator+Debug.swift
//  OBAKitCore
//
//  Created by Alan Chu on 1/4/23.
//

import Foundation

extension DataMigrator_ {

    /// Loads an arbitrary exported UserDefaults file to a new instance of DataMigrator.
    public static nonisolated func asdf(data: Data) throws -> Self? {
        let suiteName = "DataMigrator_\(Date().ISO8601Format())"
        guard let userDefaults = UserDefaults(suiteName: suiteName) else {
            return nil
        }
        userDefaults.removePersistentDomain(forName: suiteName)      // Don't persist.

        guard let migrationPrefs: [String: Any] = try Dictionary(plistData: data) else {
            return nil
        }

        for (key, value) in migrationPrefs {
            userDefaults.set(value, forKey: key)
        }

        return self.init(userDefaults: userDefaults)
    }
}
