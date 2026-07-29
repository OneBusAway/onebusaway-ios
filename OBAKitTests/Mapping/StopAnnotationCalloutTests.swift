//
//  StopAnnotationCalloutTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import MapKit
@testable import OBAKit
@testable import OBAKitCore
import Foundation
import Testing

/// Covers the gate that decides whether tapping a stop annotation shows a callout or opens the
/// stop outright. The legacy Stop page depends on the callout — it is the only way to reach the
/// chevron that pushes the stop — so a regression here silently breaks that screen's entry point.
@Suite(.serialized)
final class StopAnnotationCalloutTests: OBATestCase {

    /// `@MainActor` because `StopIconFactory` is: OBAKit builds with
    /// `SWIFT_DEFAULT_ACTOR_ISOLATION: MainActor` while OBAKitTests is `nonisolated`
    /// (see `Apps/Shared/app_shared.yml` and `OBAKitTests/project.yml`). A nested type
    /// doesn't inherit the enclosing `OBATestCase`'s isolation, so without this the
    /// `iconFactory` default value can't be evaluated in the stub's nonisolated init.
    @MainActor
    private final class StopAnnotationDelegateStub: NSObject, StopAnnotationDelegate {
        var showsStopAnnotationCallouts: Bool
        var shouldHideExtraStopAnnotationData = false
        let iconFactory = StopIconFactory(iconSize: 48.0, themeColors: ThemeColors.shared)

        init(showsStopAnnotationCallouts: Bool) {
            self.showsStopAnnotationCallouts = showsStopAnnotationCallouts
        }

        func isStopBookmarked(_ stop: Stop) -> Bool { false }
    }

    private func makeAnnotationView() -> StopAnnotationView {
        StopAnnotationView(annotation: nil, reuseIdentifier: "test")
    }

    // MARK: - StopAnnotationView

    @Test func `Annotation view without delegate shows callout`() {
        // The delegate is assigned after init, so the pre-delegate default has to be the
        // conservative one: showing a callout is recoverable, hiding one strands the legacy page.
        #expect(self.makeAnnotationView().canShowCallout)
    }

    @Test func `Annotation view delegate allows callouts shows callout`() {
        let view = makeAnnotationView()
        view.delegate = StopAnnotationDelegateStub(showsStopAnnotationCallouts: true)
        #expect(view.canShowCallout)
    }

    @Test func `Annotation view delegate suppresses callouts hides callout`() {
        let view = makeAnnotationView()
        view.delegate = StopAnnotationDelegateStub(showsStopAnnotationCallouts: false)
        #expect(!view.canShowCallout)
    }

    @Test func `Annotation view delegate reassigned recomputes callout`() {
        // Annotation views are recycled and `viewFor` reassigns the delegate on each reuse.
        let view = makeAnnotationView()
        view.delegate = StopAnnotationDelegateStub(showsStopAnnotationCallouts: false)
        view.delegate = StopAnnotationDelegateStub(showsStopAnnotationCallouts: true)
        #expect(view.canShowCallout)
    }

    // MARK: - MapRegionManager

    private func makeRegionManager() -> MapRegionManager {
        let queue = OperationQueue()
        let application = buildApplication(queue: queue, dataLoader: MockDataLoader(testName: name))
        return MapRegionManager(application: application)
    }

    @Test func `Region manager new stop page enabled suppresses callouts`() {
        userDefaults.set(true, forKey: FeatureFlags.useNewStopPageKey)
        #expect(!self.makeRegionManager().showsStopAnnotationCallouts)
    }

    @Test func `Region manager new stop page disabled keeps callouts`() {
        userDefaults.set(false, forKey: FeatureFlags.useNewStopPageKey)
        #expect(self.makeRegionManager().showsStopAnnotationCallouts)
    }

    @Test func `Region manager flag unset suppresses callouts`() {
        // `isNewStopPageEnabled` defaults to true, so an untouched install gets the sheet.
        userDefaults.removeObject(forKey: FeatureFlags.useNewStopPageKey)
        #expect(!self.makeRegionManager().showsStopAnnotationCallouts)
    }

    // MARK: - End-to-end wiring

    /// The delegate stubs above prove the rule; this proves the wiring. `viewFor` is the only
    /// place the real delegate gets attached, so a stop annotation that comes out of it has to
    /// carry the flag's answer.
    @Test @MainActor
    func `View for flag disabled stop annotation shows callout`() throws {
        userDefaults.set(false, forKey: FeatureFlags.useNewStopPageKey)
        let manager = makeRegionManager()
        let stop = try #require(Fixtures.loadSomeStops().first)

        let view = manager.mapView(manager.mapView, viewFor: stop) as? StopAnnotationView

        #expect(view?.canShowCallout == true)
    }

    @Test @MainActor
    func `View for flag enabled stop annotation suppresses callout`() throws {
        userDefaults.set(true, forKey: FeatureFlags.useNewStopPageKey)
        let manager = makeRegionManager()
        let stop = try #require(Fixtures.loadSomeStops().first)

        let view = manager.mapView(manager.mapView, viewFor: stop) as? StopAnnotationView

        #expect(view?.canShowCallout == false)
    }

    // MARK: - Staleness

    /// Turning the flag off in Settings takes effect everywhere that reads it live — the router
    /// starts returning the legacy Stop page again — but an annotation view already on the map
    /// answered the callout question at creation time. Left stale, the legacy page opens on the
    /// first tap with no callout, which is the new page's behavior on the old page's screen.
    @Test @MainActor
    func `Annotation on map flag turned off refresh restores callout`() throws {
        userDefaults.set(true, forKey: FeatureFlags.useNewStopPageKey)
        let manager = makeRegionManager()
        let stop = try #require(Fixtures.loadSomeStops().first)
        let view = try #require(manager.mapView(manager.mapView, viewFor: stop) as? StopAnnotationView)
        #expect(!view.canShowCallout)

        userDefaults.set(false, forKey: FeatureFlags.useNewStopPageKey)
        #expect(!view.canShowCallout)  // still stale...

        view.updateCalloutVisibility()
        #expect(view.canShowCallout)
    }

    /// MapKit's own re-display hook has to pick the change up too, for annotations that scroll
    /// back into view rather than sitting on screen across the flag change.
    @Test @MainActor
    func `Annotation on map flag turned on prepare for display suppresses callout`() throws {
        userDefaults.set(false, forKey: FeatureFlags.useNewStopPageKey)
        let manager = makeRegionManager()
        let stop = try #require(Fixtures.loadSomeStops().first)
        let view = try #require(manager.mapView(manager.mapView, viewFor: stop) as? StopAnnotationView)
        #expect(view.canShowCallout)

        userDefaults.set(true, forKey: FeatureFlags.useNewStopPageKey)
        view.prepareForDisplay()

        #expect(!view.canShowCallout)
    }

    @Test @MainActor
    func `Refresh stop annotation callouts with no displayed annotations is safe`() throws {
        let manager = makeRegionManager()
        manager.mapView.addAnnotation(try #require(Fixtures.loadSomeStops().first))

        manager.refreshStopAnnotationCallouts()
    }
}
