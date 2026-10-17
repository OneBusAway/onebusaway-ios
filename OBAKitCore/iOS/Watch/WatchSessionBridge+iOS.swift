//
//  WatchSessionBridge+iOS.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

#if os(iOS)
import Foundation
import WatchConnectivity

extension WatchSessionBridge {

    public var canSendToWatch: Bool {
        guard WCSession.isSupported() else { return false }
        let session = WCSession.default
        return session.activationState == .activated && session.isPaired && session.isWatchAppInstalled
    }

    public var lastSentPayload: WatchSyncPayload? {
        guard WCSession.isSupported() else { return nil }
        guard let data = WCSession.default.applicationContext["payload"] as? Data else { return nil }
        return try? WatchSyncPayload.decode(fromBinaryPlist: data)
    }

    public var lastSentRevision: String? {
        lastSentPayload?.revision
    }

    public func updateApplicationContext(data: Data) throws {
        guard canSendToWatch else { return }
        let session = WCSession.default
        try session.updateApplicationContext([
            "payload": data,
            "resendNonce": UUID().uuidString
        ])
    }

    public func send(payload: WatchSyncPayload) throws {
        let data = try payload.encodeToBinaryPlist()
        try updateApplicationContext(data: data)
    }

    // MARK: - WCSessionDelegate (iOS-only)

    nonisolated public func sessionDidBecomeInactive(_ session: WCSession) {
        // Protocol requirement on iOS
    }

    nonisolated public func sessionDidDeactivate(_ session: WCSession) {
        // Required for multi-watch switching on iOS: reactivate the session for the newly active watch.
        session.activate()
    }

    nonisolated public func sessionWatchStateDidChange(_ session: WCSession) {
        // State changed (e.g. watch app installed or pairing changed)
        notifySessionStateDidChange()
    }
}
#endif // os(iOS)
