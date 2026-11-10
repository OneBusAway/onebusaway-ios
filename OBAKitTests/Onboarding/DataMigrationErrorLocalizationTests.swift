//
//  DataMigrationErrorLocalizationTests.swift
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

/// Tests for `DataMigrationError.errorDescription`.
@MainActor
@Suite(.serialized)
final class DataMigrationErrorLocalizationTests {

    @Test func `An invalid API service error shows its explanation unchanged`() {
        let error = DataMigrationError.invalidAPIService("The region's server answered with HTTP 500.")
        #expect(error.errorDescription == "The region's server answered with HTTP 500.")
    }

    /// `OBALoc` falls back to its English literal, so comparing against that
    /// literal passes even with the key gone. Looking each key up with a sentinel
    /// fallback catches a missing key, and comparing each case to its own key
    /// catches two cases' strings being swapped. The lookup uses the bundle's
    /// preferred localization, as `OBALoc` does, so it holds in any locale.
    @Test func `Each localized data migration error shows the string for its own key`() {
        let cases: [(error: DataMigrationError, key: String)] = [
            (.noAPIServiceAvailable, "data_migration_bulletin.errors.no_api_service_available"),
            (.noDataToMigrate, "data_migration_bulletin.errors.no_data_to_migrate"),
            (.noMigrationPending, "data_migration_bulletin.errors.no_migration_pending")
        ]

        for (error, key) in cases {
            let localized = Bundle.obaKit.localizedString(forKey: key, value: "MISSING", table: nil)
            #expect(localized != "MISSING", "\(key) is missing from the strings catalog")
            #expect(error.errorDescription == localized, "\(error) should read \(key)")
        }
        #expect(Set(cases.map { $0.error.errorDescription }).count == cases.count)
    }
}
