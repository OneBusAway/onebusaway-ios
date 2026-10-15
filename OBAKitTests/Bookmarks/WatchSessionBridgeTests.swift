//
//  WatchSessionBridgeTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
import WatchConnectivity
@testable import OBAKitCore

@Suite(.serialized)
struct WatchSessionBridgeTests {

    private func makePayload(name: String) throws -> WatchSyncPayload {
        let bookmark = WatchBookmark(
            id: UUID(),
            name: name,
            regionIdentifier: 1,
            stopID: "stop_\(name)",
            stopName: "Stop \(name)",
            latitude: 47.6,
            longitude: -122.3,
            isFavorite: false
        )
        return try WatchSyncPayload(
            schemaVersion: 1,
            bookmarks: [bookmark],
            groups: [],
            region: nil
        )
    }

    @Test func `Calling delegate callback from background thread does not trap`() async throws {
        let bridge = WatchSessionBridge()
        let payload = try makePayload(name: "BackgroundTest")
        let data = try payload.encodeToBinaryPlist()

        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                if WCSession.isSupported() {
                    bridge.session(WCSession.default, didReceiveApplicationContext: ["payload": data])
                }
                continuation.resume()
            }
        }
    }

    @Test func `Stream delivers incoming payloads in FIFO order`() async throws {
        let bridge = WatchSessionBridge()
        let payloadA = try makePayload(name: "PayloadA")
        let payloadB = try makePayload(name: "PayloadB")
        let dataA = try payloadA.encodeToBinaryPlist()
        let dataB = try payloadB.encodeToBinaryPlist()

        guard WCSession.isSupported() else {
            return
        }

        let session = WCSession.default

        bridge.session(session, didReceiveApplicationContext: ["payload": dataA])
        bridge.session(session, didReceiveApplicationContext: ["payload": dataB])

        var receivedNames: [String] = []
        var iterator = bridge.payloads.makeAsyncIterator()

        if let first = await iterator.next() {
            receivedNames.append(first.bookmarks.first?.name ?? "")
        }
        if let second = await iterator.next() {
            receivedNames.append(second.bookmarks.first?.name ?? "")
        }

        #expect(receivedNames == ["PayloadA", "PayloadB"])
    }

    @Test func `Bridge handles unsupported or inactive session safely`() {
        let bridge = WatchSessionBridge()
        let dummyPayload = try? makePayload(name: "Dummy")
        if let dummyPayload {
            #expect(throws: Never.self) {
                try? bridge.send(payload: dummyPayload)
            }
        }
    }
}
