//
//  MapStatusIndicatorTests.swift
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

@Suite(.serialized)
@MainActor
struct MapStatusIndicatorTests {

    private func englishBundle() -> Bundle? {
        guard let path = Bundle.obaKit.path(forResource: "en", ofType: "lproj") else { return nil }
        return Bundle(path: path)
    }

    // MARK: - Symbol Names

    @Test func `Compact symbol names match expected SF Symbols and resolve to valid system images`() {
        let cases: [(indicator: MapStatusIndicator, expectedName: String)] = [
            (.locationUnavailable, "location.slash"),
            (.preciseLocationUnavailable, "location.circle"),
            (.zoomInForStops, "plus.magnifyingglass"),
            (.zoomInForRentals, "plus.magnifyingglass")
        ]

        for (indicator, expectedName) in cases {
            #expect(indicator.symbolName == expectedName)
            #expect(UIImage(systemName: indicator.symbolName) != nil, "\(indicator) symbol '\(expectedName)' is not a valid SF Symbol")
        }
    }

    @Test func `Large accessibility symbol names match expected filled variants and resolve to valid system images`() {
        let cases: [(indicator: MapStatusIndicator, expectedName: String)] = [
            (.locationUnavailable, "location.slash.fill"),
            (.preciseLocationUnavailable, "location.circle.fill"),
            (.zoomInForStops, "plus.magnifyingglass"),
            (.zoomInForRentals, "plus.magnifyingglass")
        ]

        for (indicator, expectedName) in cases {
            #expect(indicator.largeSymbolName == expectedName)
            #expect(UIImage(systemName: indicator.largeSymbolName) != nil, "\(indicator) large symbol '\(expectedName)' is not a valid SF Symbol")
        }
    }

    // MARK: - Localized Text & String Catalog

    @Test func `Indicator localized text matches English string catalog`() throws {
        let bundle = try #require(englishBundle())
        let activeBundle = Bundle.obaKit

        let indicators: [(indicator: MapStatusIndicator, key: String, expectedEnglish: String)] = [
            (.locationUnavailable, "map_status_view.location_services_unavailable", "Location services unavailable"),
            (.preciseLocationUnavailable, "map_status_view.precise_location_unavailable", "Precise location unavailable"),
            (.zoomInForStops, "map_status_view.zoom_in_for_stops", "Zoom in for stops"),
            (.zoomInForRentals, "map_status_view.zoom_in_for_rentals", "Zoom in to see bikes and scooters")
        ]

        for (indicator, key, expectedEnglish) in indicators {
            let catalogString = bundle.localizedString(forKey: key, value: "MISSING", table: nil)
            #expect(catalogString != "MISSING", "\(key) is missing from the English catalog")
            #expect(catalogString == expectedEnglish, "\(key) has unexpected translation in English catalog")

            let activeString = activeBundle.localizedString(forKey: key, value: "MISSING", table: nil)
            #expect(indicator.localizedText == activeString, "\(indicator) localizedText did not match catalog translation for \(key)")
            #expect(indicator.accessibilityAnnouncement == indicator.localizedText)
        }
    }

    // MARK: - VoiceOver Announcements

    private func makeMountedStatusView() -> (window: UIWindow, statusView: MapStatusView) {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let statusView = MapStatusView(frame: CGRect(x: 0, y: 0, width: 220, height: 40))
        window.addSubview(statusView)
        return (window, statusView)
    }

    @Test func `Unmounted status view suppresses VoiceOver announcements until mounted in a window`() throws {
        let unmounted = MapStatusView()
        var unmountedPosts = 0
        unmounted.accessibilityAnnouncer = { _, _ in unmountedPosts += 1 }
        unmounted.configure(for: .locationServicesOn, zoomInStatus: true)
        #expect(unmountedPosts == 0)

        let (window, mounted) = makeMountedStatusView()
        defer { window.isHidden = true }
        var mountedPosts: [String] = []
        mounted.accessibilityAnnouncer = { notification, argument in
            #expect(notification == .announcement)
            if let attributed = argument as? NSAttributedString {
                mountedPosts.append(attributed.string)
            }
        }
        mounted.configure(for: .locationServicesOn, zoomInStatus: true)
        #expect(mountedPosts == [MapStatusIndicator.zoomInForStops.localizedText])
    }

    @Test func `Visible indicator transitions post queued VoiceOver announcements`() throws {
        let (window, statusView) = makeMountedStatusView()
        defer { window.isHidden = true }
        var posted: [(notification: UIAccessibility.Notification, argument: Any?)] = []
        statusView.accessibilityAnnouncer = { notification, argument in
            posted.append((notification, argument))
        }

        statusView.configure(for: .locationServicesOn, zoomInStatus: true)
        statusView.configure(for: .impreciseLocation, zoomInStatus: false)
        statusView.configure(for: .locationServicesOn, zoomInStatus: false, rentalZoomInStatus: true)
        statusView.configure(for: .locationServicesOff, zoomInStatus: false)

        #expect(posted.count == 4)
        let expectedTexts = [
            MapStatusIndicator.zoomInForStops.localizedText,
            MapStatusIndicator.preciseLocationUnavailable.localizedText,
            MapStatusIndicator.zoomInForRentals.localizedText,
            MapStatusIndicator.locationUnavailable.localizedText
        ]
        for (entry, expectedText) in zip(posted, expectedTexts) {
            #expect(entry.notification == .announcement)
            let attributed = try #require(entry.argument as? NSAttributedString)
            #expect(attributed.string == expectedText)
            let queued = attributed.attribute(.accessibilitySpeechQueueAnnouncement, at: 0, effectiveRange: nil) as? Bool
            #expect(queued == true)
        }
    }

    @Test func `Unchanged or hidden transitions skip duplicate and empty VoiceOver announcements`() throws {
        let (window, statusView) = makeMountedStatusView()
        defer { window.isHidden = true }
        var postedMessages: [String] = []
        statusView.accessibilityAnnouncer = { notification, argument in
            #expect(notification == .announcement)
            if let attributed = argument as? NSAttributedString {
                postedMessages.append(attributed.string)
            } else if let text = argument as? String {
                postedMessages.append(text)
            }
        }

        // Hidden initially -> hidden: no announcement.
        statusView.configure(for: .locationServicesOn, zoomInStatus: false)
        #expect(postedMessages.isEmpty)

        // Visible -> same indicator repeated: announced once.
        statusView.configure(for: .locationServicesOn, zoomInStatus: true)
        statusView.configure(for: .locationServicesOn, zoomInStatus: true)
        #expect(postedMessages == [MapStatusIndicator.zoomInForStops.localizedText])

        // Distinct location states mapping to the same indicator (.locationUnavailable): announced once.
        statusView.configure(for: .notDetermined, zoomInStatus: false)
        statusView.configure(for: .locationServicesOff, zoomInStatus: false)
        statusView.configure(for: .locationServicesUnavailable, zoomInStatus: false)
        #expect(postedMessages == [
            MapStatusIndicator.zoomInForStops.localizedText,
            MapStatusIndicator.locationUnavailable.localizedText
        ])

        // Hiding posts nothing; returning to a visible status announces again.
        statusView.configure(for: .locationServicesOn, zoomInStatus: false)
        #expect(postedMessages.count == 2)

        statusView.configure(for: .locationServicesOn, zoomInStatus: true)
        #expect(postedMessages == [
            MapStatusIndicator.zoomInForStops.localizedText,
            MapStatusIndicator.locationUnavailable.localizedText,
            MapStatusIndicator.zoomInForStops.localizedText
        ])
    }

    // MARK: - Large Content Viewer & Accessibility Element

    @Test func `Status view configures Large Content Viewer properties and interaction`() throws {
        struct PillCase {
            let state: MapStatusView.LocationState
            let zoomStops: Bool
            let zoomRentals: Bool
            let expectedIndicator: MapStatusIndicator
        }

        let statusView = MapStatusView()

        #expect(statusView.showsLargeContentViewer)
        #expect(statusView.scalesLargeContentImage)
        let interaction = try #require(
            statusView.interactions.compactMap { $0 as? UILargeContentViewerInteraction }.first
        )
        #expect(interaction.delegate === statusView)

        let cases = [
            PillCase(state: .locationServicesOn, zoomStops: true, zoomRentals: false, expectedIndicator: .zoomInForStops),
            PillCase(state: .locationServicesOn, zoomStops: false, zoomRentals: true, expectedIndicator: .zoomInForRentals),
            PillCase(state: .impreciseLocation, zoomStops: false, zoomRentals: false, expectedIndicator: .preciseLocationUnavailable),
            PillCase(state: .locationServicesOff, zoomStops: false, zoomRentals: false, expectedIndicator: .locationUnavailable)
        ]

        for item in cases {
            statusView.configure(for: item.state, zoomInStatus: item.zoomStops, rentalZoomInStatus: item.zoomRentals)
            #expect(statusView.largeContentTitle == item.expectedIndicator.localizedText)
            #expect(statusView.largeContentImage != nil)
            #expect(statusView.isAccessibilityElement)
            #expect(statusView.accessibilityLabel == item.expectedIndicator.localizedText)
            #expect(statusView.accessibilityTraits == .button)
        }

        // System-restricted location cannot be changed by tapping.
        statusView.configure(for: .locationServicesUnavailable, zoomInStatus: false)
        #expect(statusView.accessibilityTraits == .staticText)

        // Hidden state clears large content text/image and disables accessibility element.
        statusView.configure(for: .locationServicesOn, zoomInStatus: false)
        #expect(statusView.largeContentTitle == nil)
        #expect(statusView.largeContentImage == nil)
        #expect(!statusView.isAccessibilityElement)
        #expect(statusView.accessibilityLabel == nil)
    }

    @Test func `Large content viewer lift triggers activation only when visible, targeting self, and within bounds`() throws {
        let statusView = MapStatusView(frame: CGRect(x: 0, y: 0, width: 220, height: 40))
        let interaction = try #require(
            statusView.interactions.compactMap { $0 as? UILargeContentViewerInteraction }.first
        )
        var activations = 0
        statusView.onLargeContentViewerActivate = { activations += 1 }

        // Hidden pill should not activate.
        statusView.largeContentViewerInteraction(interaction, didEndOn: statusView, at: CGPoint(x: 10, y: 10))
        #expect(activations == 0)

        // Visible pill ignores nil item inside bounds and statusView item outside bounds.
        statusView.configure(for: .locationServicesOn, zoomInStatus: true)
        statusView.largeContentViewerInteraction(interaction, didEndOn: nil, at: CGPoint(x: 20, y: 20))
        #expect(activations == 0)
        statusView.largeContentViewerInteraction(interaction, didEndOn: statusView, at: CGPoint(x: 500, y: 500))
        #expect(activations == 0)

        // Activates only when visible, item === statusView, and point is inside bounds.
        statusView.largeContentViewerInteraction(interaction, didEndOn: statusView, at: CGPoint(x: 20, y: 20))
        #expect(activations == 1)
    }
}
