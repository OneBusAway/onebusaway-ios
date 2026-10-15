//
//  WatchBookmarkStore.swift
//  OBAKitWatch
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Observation
import OBAKitCore

/// Reads and writes the cached `WatchSyncPayload` in the on-watch app group container.
@MainActor
@Observable
public final class WatchBookmarkStore {
    public static let payloadKey = "watch_sync_payload"

    @ObservationIgnored private let userDefaults: UserDefaults

    public private(set) var payload: WatchSyncPayload?

    public var bookmarks: [WatchBookmark] {
        payload?.bookmarks ?? []
    }

    public var groups: [WatchBookmarkGroup] {
        payload?.groups ?? []
    }

    public var syncedRegion: Region? {
        payload?.region
    }

    public init(userDefaults: UserDefaults) {
        self.userDefaults = userDefaults
        if let data = userDefaults.data(forKey: Self.payloadKey) {
            self.payload = try? WatchSyncPayload.decode(fromBinaryPlist: data)
        }
    }

    public func update(payload: WatchSyncPayload) {
        guard self.payload?.revision != payload.revision else { return }
        self.payload = payload
        if let data = try? payload.encodeToBinaryPlist() {
            userDefaults.set(data, forKey: Self.payloadKey)
        }
    }
}
