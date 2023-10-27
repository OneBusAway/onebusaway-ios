//
//  OBAKitCorePersistenceTestCase.swift
//  OBAKitCoreTests
// 
//  Copyright © 2023 Open Transit Software Foundation.
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import XCTest
@testable import OBAKitCore

open class OBAKitCorePersistenceTestCase: OBAKitCoreTestCase {
    var persistence: PersistenceService!

    override open func setUp() async throws {
        try await super.setUp()

        let configuration = PersistenceService.Configuration(
            regionIdentifier: 999,
            databaseLocation: .memory
        )
        persistence = try PersistenceService(configuration)
    }
}
