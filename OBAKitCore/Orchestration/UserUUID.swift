//
//  UserUUID.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

/// A unique (but not personally-identifying) identifier for the current user,
/// used to correlate crash logs and API requests to a single install.
///
/// A free-standing helper rather than a `CoreApplication` property so that a
/// widget extension can identify itself to the REST API without constructing a
/// `CoreApplication` — which starts a regions fetch, opens the stop cache, and
/// bumps the launch counter. Pass the app-group suite and the extension shares
/// the app's identifier.
public enum UserUUID {
    public static let defaultsKey = "userUUIDDefaultsKey"

    public static func value(in userDefaults: UserDefaults) -> String {
        if let uuid = userDefaults.object(forKey: defaultsKey) as? String {
            return uuid
        }

        let uuid = UUID().uuidString
        userDefaults.set(uuid, forKey: defaultsKey)
        return uuid
    }
}
