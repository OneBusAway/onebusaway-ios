//
//  WatchSessionBridge.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import WatchConnectivity

public final class WatchSessionBridge: NSObject, WCSessionDelegate, @unchecked Sendable {
    public static let shared = WatchSessionBridge()

    public let payloads: AsyncStream<WatchSyncPayload>
    private let payloadContinuation: AsyncStream<WatchSyncPayload>.Continuation

    public override init() {
        let (stream, continuation) = AsyncStream<WatchSyncPayload>.makeStream()
        self.payloads = stream
        self.payloadContinuation = continuation
        super.init()
    }

    public func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    public var isSupported: Bool {
        WCSession.isSupported()
    }

    public var latestReceivedPayload: WatchSyncPayload? {
        guard WCSession.isSupported() else { return nil }
        guard let data = WCSession.default.receivedApplicationContext["payload"] as? Data else { return nil }
        return try? WatchSyncPayload.decode(fromBinaryPlist: data)
    }

    // MARK: - WCSessionDelegate

    nonisolated public func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: (any Error)?
    ) {
        if let error {
            Logger.warn("WatchSessionBridge: activation failed with error: \(error.localizedDescription)")
        }
        if activationState == .activated {
            notifySessionStateDidChange()
        }
    }

    nonisolated public func session(
        _ session: WCSession,
        didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        // Extract Data blob immediately; Data is Sendable, [String: Any] is not.
        guard let data = applicationContext["payload"] as? Data else { return }
        guard let payload = try? WatchSyncPayload.decode(fromBinaryPlist: data) else { return }
        payloadContinuation.yield(payload)
    }

    nonisolated func notifySessionStateDidChange() {
        NotificationCenter.default.post(name: .watchSessionStateDidChange, object: self)
    }
}

extension Notification.Name {
    /// Posted when a WatchConnectivity session activates or when the companion watch state changes.
    public static let watchSessionStateDidChange = Notification.Name("OBAWatchSessionStateDidChangeNotification")
}
