//
//  NearbyStopsListAccessibilityTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreLocation
import Foundation
import Testing
import UIKit
@testable import OBAKit
@testable import OBAKitCore

/// The nearby-stops list is a VoiceOver rider's main way to a stop. Its rows read
/// "Pine St & 3rd Ave (W)" as the letter W, weren't announced as buttons, and gave
/// no distance, and its section header wasn't a heading.
@MainActor
@Suite(.serialized)
final class NearbyStopsListAccessibilityTests {

    private final class DataSource: NearbyStopsListDataSource {
        var highSeverityAlerts: [AgencyAlert] = []
        var stops: [Stop] = []
        var userLocation: CLLocation?
    }

    private let dataSource = DataSource()
    private let stops: [Stop]

    init() throws {
        stops = Array(try Fixtures.loadSomeStops().prefix(3))
    }

    /// Cells in list order: the header, then one per stop.
    private func cells() throws -> [UICollectionViewCell] {
        let controller = NearbyStopsListViewController()
        controller.dataSource = dataSource
        controller.view.frame = CGRect(x: 0, y: 0, width: 390, height: 2000)
        controller.updateList()
        controller.view.layoutIfNeeded()

        let collectionView = try #require(controller.scrollView as? UICollectionView)
        return try (0...dataSource.stops.count).map { item in
            try #require(collectionView.cellForItem(at: IndexPath(item: item, section: 0)))
        }
    }

    @Test func `Stop rows say what the map pin says, and are buttons`() throws {
        dataSource.stops = stops
        let rows = try cells().dropFirst()

        for (row, stop) in zip(rows, stops) {
            let label = try #require(row.accessibilityLabel)
            #expect(label.hasPrefix(Formatters.formattedAccessibilityLabel(stop: stop)))
            #expect(row.accessibilityTraits.contains(.button))
            #expect(row.accessibilityHint == StopAnnotationView.accessibilityHint)
            #expect(row.accessibilityValue == nil)
        }
    }

    @Test func `Stop rows keep primary label uncluttered without duplicate alert`() throws {
        let stop = stops[0]
        let label = NearbyStopsListViewController.accessibilityLabel(for: stop, from: nil)
        #expect(!label.contains(Strings.serviceAlert))
    }

    @Test func `Stop rows give the distance from the rider when it's known`() throws {
        let stop = stops[0]
        dataSource.stops = [stop]
        let rider = CLLocation(latitude: stop.location.coordinate.latitude + 0.002, longitude: stop.location.coordinate.longitude)
        dataSource.userLocation = rider

        let row = try cells()[1]
        let distance = Formatters.spokenDistanceFormatter.string(fromDistance: stop.location.distance(from: rider))
        #expect(row.accessibilityLabel?.contains(distance) == true)
    }

    @Test func `The section header is a heading`() throws {
        dataSource.stops = stops
        let header = try cells()[0]
        #expect(header.accessibilityTraits.contains(.header))
        #expect(!header.accessibilityTraits.contains(.button))
    }

    private func makeAgencyAlert(id: String, title: String) throws -> AgencyAlert {
        var entitySelector = TransitRealtime_EntitySelector()
        entitySelector.agencyID = ""

        var titleTranslation = TransitRealtime_TranslatedString.Translation()
        titleTranslation.language = "en"
        titleTranslation.text = title

        var transitAlert = TransitRealtime_Alert()
        transitAlert.informedEntity = [entitySelector]
        transitAlert.headerText.translation = [titleTranslation]

        var feedEntity = TransitRealtime_FeedEntity()
        feedEntity.id = id
        feedEntity.alert = transitAlert

        return try AgencyAlert(feedEntity: feedEntity, agency: nil)
    }

    @Test func `Alert rows clear accessibilityHint so reused cells do not keep stop hint`() throws {
        let alert = try makeAgencyAlert(id: "alert_1", title: "Snow route active")
        dataSource.highSeverityAlerts = [alert]
        dataSource.stops = [stops[0]]

        let controller = NearbyStopsListViewController()
        controller.dataSource = dataSource
        controller.view.frame = CGRect(x: 0, y: 0, width: 390, height: 2000)
        controller.updateList()
        controller.view.layoutIfNeeded()

        let collectionView = try #require(controller.scrollView as? UICollectionView)
        // Alert section is section 0; item 0 is header, item 1 is alert row.
        let alertRow = try #require(collectionView.cellForItem(at: IndexPath(item: 1, section: 0)))
        // Stops section is section 1; item 0 is header, item 1 is stop row.
        let stopRow = try #require(collectionView.cellForItem(at: IndexPath(item: 1, section: 1)))

        #expect(stopRow.accessibilityHint == StopAnnotationView.accessibilityHint)
        #expect(alertRow.accessibilityHint == nil)
    }

    // MARK: - StopAnnotationView Dynamic Type

    private final class AnnotationDelegateStub: NSObject, StopAnnotationDelegate {
        let shouldHideExtraStopAnnotationData = false
        let clustersStops = false
        let iconFactory = StopIconFactory(iconSize: ThemeMetrics.defaultMapAnnotationSize, themeColors: ThemeColors.shared)

        func isStopBookmarked(_ stop: Stop) -> Bool { false }
    }

    private static let allContentSizeCategories: [UIContentSizeCategory] = [
        .extraSmall,
        .small,
        .medium,
        .large,
        .extraLarge,
        .extraExtraLarge,
        .extraExtraExtraLarge,
        .accessibilityMedium,
        .accessibilityLarge,
        .accessibilityExtraLarge,
        .accessibilityExtraExtraLarge,
        .accessibilityExtraExtraExtraLarge
    ]

    @Test func `Stop annotation font scales proportionally across all content size categories without turning tiny`() throws {
        let view = StopAnnotationView(annotation: stops[0], reuseIdentifier: nil)
        let sampleText = "10, 20, 30…"

        var sizes: [CGFloat] = []
        for category in Self.allContentSizeCategories {
            let traits = UITraitCollection(preferredContentSizeCategory: category)
            let attributed = view.strokedText(sampleText, compatibleWith: traits)
            let font = try #require(attributed.attribute(.font, at: 0, effectiveRange: nil) as? UIFont)

            #expect(font.pointSize >= StopAnnotationView.LabelTypography.minimumPointSize)
            #expect(font.pointSize <= StopAnnotationView.LabelTypography.maximumPointSize)
            sizes.append(font.pointSize)
        }

        for index in 1..<sizes.count {
            #expect(sizes[index] >= sizes[index - 1])
        }

        let extraSmallSize = sizes[0]
        let largeSize = sizes[3]
        let maxA11ySize = try #require(sizes.last)

        #expect(largeSize == StopAnnotationView.LabelTypography.basePointSize)
        #expect(extraSmallSize < largeSize)
        #expect(maxA11ySize > largeSize)
    }

    @Test func `Stop annotation strokedText bounding box fits within view bounds across all content size categories`() throws {
        let delegate = AnnotationDelegateStub()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let container = UIView(frame: window.bounds)
        window.addSubview(container)
        window.makeKeyAndVisible()
        defer { window.isHidden = true }

        let view = StopAnnotationView(annotation: stops[0], reuseIdentifier: nil)
        view.delegate = delegate
        container.addSubview(view)
        view.center = CGPoint(x: container.bounds.midX, y: container.bounds.midY)

        for category in Self.allContentSizeCategories {
            view.traitOverrides.preferredContentSizeCategory = category
            view.updateTraitsIfNeeded()
            view.prepareForDisplay()
            view.layoutIfNeeded()

            let attributed = try #require(view.titleLabel.attributedText)
            let labelBounds = view.titleLabel.bounds
            #expect(labelBounds.width >= view.bounds.width - 0.5)
            #expect(labelBounds.width <= view.maxLabelWidth + 0.5)

            let measured = attributed.boundingRect(
                with: CGSize(width: labelBounds.width, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                context: nil
            )
            #expect(measured.width <= labelBounds.width + 1.0)
            #expect(measured.height <= labelBounds.height + 1.0)
        }
    }

    @Test func `Stop annotation updates label font on content size trait changes and clamps long bookmark names`() throws {
        let delegate = AnnotationDelegateStub()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.makeKeyAndVisible()
        defer { window.isHidden = true }

        let bookmark = Bookmark(name: "University District Station", regionIdentifier: 1, stop: stops[0])
        let view = StopAnnotationView(annotation: bookmark, reuseIdentifier: nil)
        view.delegate = delegate
        window.addSubview(view)
        view.center = CGPoint(x: window.bounds.midX, y: window.bounds.midY)

        view.traitOverrides.preferredContentSizeCategory = .large
        view.updateTraitsIfNeeded()
        view.prepareForDisplay()
        view.layoutIfNeeded()

        let standardAttributed = try #require(view.titleLabel.attributedText)
        let standardFont = try #require(standardAttributed.attribute(.font, at: 0, effectiveRange: nil) as? UIFont)

        // Switching Dynamic Type trait should automatically trigger rebuild via registerForTraitChanges
        view.traitOverrides.preferredContentSizeCategory = .accessibilityExtraExtraExtraLarge
        view.updateTraitsIfNeeded()
        view.layoutIfNeeded()

        let a11yAttributed = try #require(view.titleLabel.attributedText)
        let a11yFont = try #require(a11yAttributed.attribute(.font, at: 0, effectiveRange: nil) as? UIFont)
        #expect(a11yFont.pointSize >= standardFont.pointSize)
        #expect(a11yFont.pointSize >= StopAnnotationView.LabelTypography.minimumPointSize)
        #expect(a11yFont.pointSize <= StopAnnotationView.LabelTypography.maximumPointSize)

        let labelBounds = view.titleLabel.bounds
        #expect(labelBounds.width <= view.maxLabelWidth + 0.5)
        let measured = a11yAttributed.boundingRect(
            with: CGSize(width: labelBounds.width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )
        #expect(measured.width <= labelBounds.width + 1.0)
        #expect(measured.height <= labelBounds.height + 1.0)
    }
}
