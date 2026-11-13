//
//  AlarmRemoverTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
@testable import OBAKit
@testable import OBAKitCore

/// The one way the stop page, the trip page and the Recent tab delete an alarm.
@Suite(.serialized)
@MainActor
final class AlarmRemoverTests: OBATestCase {
    private let notificationCenter = NotificationCenter()
    /// "server" and "local", in the order they happened.
    private let steps = SendableBox<[String]>([])
    private var postedURLs: [URL] = []
    private var observer: NSObjectProtocol?

    override init() async throws {
        try await super.init()
        observer = notificationCenter.addObserver(forName: .alarmRemoved, object: nil, queue: nil) { [weak self] note in
            guard let url = note.userInfo?[AlarmRemover.alarmURLKey] as? URL else { return }
            MainActor.assumeIsolated { self?.postedURLs.append(url) }
        }
    }

    private func remover(dataLoader: MockDataLoader?) -> AlarmRemover {
        AlarmRemover(
            obacoService: dataLoader.map { buildObacoService(dataLoader: $0) },
            deleteLocalCopy: { [steps] _ in steps.value.append("local") },
            notificationCenter: notificationCenter
        )
    }

    private func stubDelete(_ dataLoader: MockDataLoader, statusCode: Int = 200) {
        dataLoader.mock(data: Data(), statusCode: statusCode) { [steps] request in
            guard request.url?.path.contains("/alarms/") == true else { return false }
            steps.value.append("server")
            return true
        }
    }

    @Test func `The server copy goes first, then the local one, then the news`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        stubDelete(dataLoader)
        let alarm = try Fixtures.loadAlarm()

        try await remover(dataLoader: dataLoader).remove(alarm)

        #expect(steps.value == ["server", "local"])
        #expect(postedURLs == [alarm.url])
    }

    /// The rider can still see the alarm, and cancel it again.
    @Test func `A server failure keeps the local copy and says nothing`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        stubDelete(dataLoader, statusCode: 500)
        let alarm = try Fixtures.loadAlarm()

        await #expect(throws: (any Error).self) {
            try await self.remover(dataLoader: dataLoader).remove(alarm)
        }

        #expect(steps.value == ["server"])
        #expect(postedURLs.isEmpty)
    }

    /// The server deletes an alarm once it fires.
    @Test func `An alarm the server no longer has counts as deleted`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        stubDelete(dataLoader, statusCode: 404)
        let alarm = try Fixtures.loadAlarm()

        try await remover(dataLoader: dataLoader).remove(alarm)

        #expect(steps.value == ["server", "local"])
        #expect(postedURLs == [alarm.url])
    }

    /// The server alarm would still fire, with nothing left in the app to stop it.
    @Test func `Without an alarm service nothing is deleted`() async throws {
        let alarm = try Fixtures.loadAlarm()

        await #expect(throws: StopViewModel.AlarmCancellationError.self) {
            try await self.remover(dataLoader: nil).remove(alarm)
        }

        #expect(steps.value.isEmpty)
        #expect(postedURLs.isEmpty)
    }
}
