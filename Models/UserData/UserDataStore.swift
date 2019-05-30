//
//  UserDataStore.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 5/18/19.
//

import Foundation
import CocoaLumberjackSwift

/// `UserDataStore` is a repository for the user's data, such as bookmarks, and recent stops.
///
/// This protocol is designed to support pluggable data storage layers, so that services ranging
/// from UserDefaults, CloudKit, Firebase, or custom persistence systems (local or remote)
/// could be used to store a user's data.
@objc(OBAUserDataStore)
public protocol UserDataStore: NSObjectProtocol {

    /// A list of recently-viewed stops
    var recentStops: [Stop] { get }

    /// Add a `Stop` to the list of recently-viewed `Stop`s
    ///
    /// - Parameter stop: The stop to add to the list
    func addRecentStop(_ stop: Stop)

    /// The maximum number of recent stops that will be stored.
    var maximumRecentStopsCount: Int { get }
}

@objc(OBAUserDefaultsStore)
public class UserDefaultsStore: NSObject, UserDataStore {
    let userDefaults: UserDefaults

    enum UserDefaultsKeys: String {
        case recentStops
    }

    public init(userDefaults: UserDefaults) {
        self.userDefaults = userDefaults
    }

    // MARK: - Recent Stops

    public var recentStops: [Stop] {
        get {
            guard let stopData = try? userDefaults.object(type: Data.self, forKey: UserDefaultsKeys.recentStops.rawValue) else {
                return []
            }

            do {
                return try PropertyListDecoder().decode([Stop].self, from: stopData)
            }
            catch let error {
                DDLogError("Unable to decode recent stops: \(error)")
                return []
            }
        }
        set {
            let encoded = try! PropertyListEncoder().encode(newValue) // swiftlint:disable:this force_try
            userDefaults.set(encoded, forKey: UserDefaultsKeys.recentStops.rawValue)
        }
    }

    public func addRecentStop(_ stop: Stop) {
        var recentStops = self.recentStops

        if let idx = recentStops.firstIndex(of: stop) {
            recentStops.remove(at: idx)
        }
        recentStops.insert(stop, at: 0)

        if recentStops.count > maximumRecentStopsCount {
            self.recentStops = Array(recentStops[0..<maximumRecentStopsCount])
        }
        else {
            self.recentStops = recentStops
        }
    }

    public var maximumRecentStopsCount: Int {
        return 20
    }
}
