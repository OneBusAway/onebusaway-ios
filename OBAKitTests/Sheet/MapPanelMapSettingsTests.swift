//
//  MapPanelMapSettingsTests.swift
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

/// Settings' Show Scale, Show Traffic and Show Heading switches went to
/// `MapRegionManager`'s `MKMapView` only, which the map panel never shows.
@MainActor
@Suite(.serialized)
final class MapPanelMapSettingsTests: OBATestCase {

    private func makePanelSettings(_ application: Application) -> MapPanelMapSettings {
        MapPanelMapSettings(style: .standard(pointsOfInterest: true), userDefaults: application.userDefaults)
    }

    @Test func `Both maps start with every switch on`() {
        let application = buildApplication(queue: OperationQueue(), dataLoader: MockDataLoader(testName: name))
        let manager = application.mapRegionManager
        let panel = makePanelSettings(application)

        #expect(manager.mapViewShowsScale)
        #expect(MapDisplaySettings(userDefaults: application.userDefaults).showsTraffic)
        #expect(manager.mapViewShowsHeading)

        #expect(panel.showsScale)
        #expect(panel.showsTraffic)
        #expect(MapPanelUserLocation(userDefaults: application.userDefaults).showsHeading)
    }

    @Test func `The panel map reads the switches Settings writes`() {
        let application = buildApplication(queue: OperationQueue(), dataLoader: MockDataLoader(testName: name))

        application.mapRegionManager.mapViewShowsScale = false
        application.mapRegionManager.mapViewShowsTraffic = false

        let panel = makePanelSettings(application)
        #expect(!panel.showsScale)
        #expect(!panel.showsTraffic)
    }

    @Test func `The panel's location reads the Show Heading switch Settings writes`() {
        let application = buildApplication(queue: OperationQueue(), dataLoader: MockDataLoader(testName: name))
        let settings = SettingsViewModel(application: application)

        settings.mapShowsHeading = false
        #expect(!MapPanelUserLocation(userDefaults: application.userDefaults).showsHeading)

        settings.mapShowsHeading = true
        #expect(MapPanelUserLocation(userDefaults: application.userDefaults).showsHeading)
    }

    @Test func `The stored keys keep riders' existing choices`() {
        #expect(MapDisplaySettings.showsScaleKey == "mapRegionManager.mapViewShowsScale")
        #expect(MapDisplaySettings.showsTrafficKey == "mapRegionManager.mapViewShowsTraffic")
        #expect(MapDisplaySettings.showsHeadingKey == "mapRegionManager.mapViewShowsHeadingKey")
    }

    @Test func `Traffic stays off in the Simulator`() {
        #if targetEnvironment(simulator)
        #expect(!MapDisplaySettings.effectiveShowsTraffic(true))
        #else
        #expect(MapDisplaySettings.effectiveShowsTraffic(true))
        #endif
        #expect(!MapDisplaySettings.effectiveShowsTraffic(false))
    }
}
