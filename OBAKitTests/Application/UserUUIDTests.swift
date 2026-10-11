//
//  UserUUIDTests.swift
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

@Suite(.serialized)
final class UserUUIDTests: OBATestCase {

    @Test func `Creates a UUID once and returns the same one afterwards`() {
        let first = UserUUID.value(in: userDefaults)
        let second = UserUUID.value(in: userDefaults)

        #expect(UUID(uuidString: first) != nil)
        #expect(first == second)
    }

    @Test func `Reads an identifier an earlier version already stored`() {
        userDefaults.set("existing-id", forKey: "userUUIDDefaultsKey")
        #expect(UserUUID.value(in: userDefaults) == "existing-id")
    }

    /// A widget reading the app-group suite must get the app's identifier,
    /// not mint a second one.
    @Test @MainActor func `Matches what CoreApplication reports for the same suite`() {
        let queue = OperationQueue()
        let application = buildApplication(queue: queue, dataLoader: MockDataLoader(testName: name))

        #expect(UserUUID.value(in: userDefaults) == application.userUUID)
        queue.cancelAllOperations()
    }
}
