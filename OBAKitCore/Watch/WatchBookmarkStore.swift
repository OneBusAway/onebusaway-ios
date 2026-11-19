//
//  WatchBookmarkStore.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Observation

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

    /// Updates the stored payload.
    ///
    /// Ignores duplicate payloads (identical revision) and out-of-order deliveries (older sequence number).
    /// Resolves ties deterministically by comparing revision hashes.
    ///
    /// - Parameter payload: The candidate payload received from the companion device.
    /// - Returns: `true` if the payload was applied and persisted; `false` if rejected.
    @discardableResult
    public func update(payload: WatchSyncPayload) -> Bool {
        if let current = self.payload {
            let isSameEpoch: Bool
            if let currentEpoch = current.epoch, let newEpoch = payload.epoch {
                isSameEpoch = (currentEpoch == newEpoch)
            } else if current.epoch == nil && payload.epoch == nil {
                isSameEpoch = true
            } else {
                isSameEpoch = false
            }

            if isSameEpoch {
                // 1. Duplicate payload check: if revision is identical and sequence does not advance, ignore.
                guard current.revision != payload.revision
                    || payload.sequenceNumber > current.sequenceNumber else {
                    return false
                }

                // 2. Out-of-order check: if both payloads have positive sequence numbers,
                // reject an older sequence number arriving late.
                if current.sequenceNumber > 0, payload.sequenceNumber > 0 {
                    if payload.sequenceNumber < current.sequenceNumber {
                        return false
                    }
                    if payload.sequenceNumber == current.sequenceNumber {
                        // Same sequence number: tie-break deterministically using revision hash comparison.
                        if payload.revision <= current.revision {
                            return false
                        }
                    }
                }
            }
        }

        self.payload = payload
        if let data = try? payload.encodeToBinaryPlist() {
            userDefaults.set(data, forKey: Self.payloadKey)
        }
        return true
    }

    /// Clears the stored payload and removes it from UserDefaults.
    public func clear() {
        self.payload = nil
        userDefaults.removeObject(forKey: Self.payloadKey)
    }
}
