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

    public var canSendToWatch: Bool {
        guard WCSession.isSupported() else { return false }
        let session = WCSession.default
        #if os(iOS)
        return session.activationState == .activated && session.isPaired && session.isWatchAppInstalled
        #else
        return session.activationState == .activated
        #endif
    }

    public var lastSentPayload: WatchSyncPayload? {
        guard WCSession.isSupported() else { return nil }
        guard let data = WCSession.default.applicationContext["payload"] as? Data else { return nil }
        return try? WatchSyncPayload.decode(fromBinaryPlist: data)
    }

    public var lastSentRevision: String? {
        lastSentPayload?.revision
    }

    public var latestReceivedPayload: WatchSyncPayload? {
        guard WCSession.isSupported() else { return nil }
        guard let data = WCSession.default.receivedApplicationContext["payload"] as? Data else { return nil }
        return try? WatchSyncPayload.decode(fromBinaryPlist: data)
    }

    public func updateApplicationContext(data: Data) throws {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        #if os(iOS)
        guard session.activationState == .activated && session.isPaired && session.isWatchAppInstalled else {
            return
        }
        #else
        guard session.activationState == .activated else {
            return
        }
        #endif
        try session.updateApplicationContext(["payload": data])
    }

    public func send(payload: WatchSyncPayload) throws {
        let data = try payload.encodeToBinaryPlist()
        try updateApplicationContext(data: data)
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

    #if os(iOS)
    nonisolated public func sessionDidBecomeInactive(_ session: WCSession) {
        // Protocol requirement on iOS
    }

    nonisolated public func sessionDidDeactivate(_ session: WCSession) {
        // Required for multi-watch switching on iOS
        session.activate()
    }

    nonisolated public func sessionWatchStateDidChange(_ session: WCSession) {
        // State changed (e.g. watch app installed or pairing changed)
    }
    #endif
}
