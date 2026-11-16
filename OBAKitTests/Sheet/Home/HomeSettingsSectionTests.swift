//
//  HomeSettingsSectionTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
import UIKit
@testable import OBAKit
@testable import OBAKitCore

/// The home sheet's Settings and More section: the map's options, settings and More.
@Suite
@MainActor
struct HomeSettingsSectionTests {
    /// More has nowhere else to live on iPhone; regular width has its button on the map.
    @Test func `More comes last, and only where it's offered`() {
        #expect(HomeSettingsItem.items(offersMore: true) == [.customizeMap, .settings, .more])
        #expect(HomeSettingsItem.items(offersMore: false) == [.customizeMap, .settings])
    }

    @Test func `Every row has a title, a subtitle and a symbol that exists`() {
        for item in HomeSettingsItem.allCases {
            #expect(!item.title.isEmpty)
            #expect(!item.subtitle.isEmpty)
            #expect(UIImage(systemName: item.systemImage) != nil)
        }
    }

    @Test func `Rows read as specified`() {
        #expect(HomeSettingsItem.customizeMap.title == "Customize Map")
        #expect(HomeSettingsItem.customizeMap.subtitle == "Change map display options")
        #expect(HomeSettingsItem.settings.title == "Settings")
        #expect(HomeSettingsItem.settings.subtitle == "Change app settings")
        #expect(HomeSettingsItem.more.title == "More")
        #expect(HomeSettingsItem.more.subtitle == "Donate, Change Region, Give Feedback, and more")
        #expect(Strings.settingsAndMore == "Settings and More")
    }
}
