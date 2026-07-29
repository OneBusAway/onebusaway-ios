//
//  StopAnnotationCalloutTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import XCTest
import MapKit
@testable import OBAKit
@testable import OBAKitCore
import Testing

/// Covers the gate that decides whether tapping a stop annotation shows a callout or opens the
/// stop outright. The legacy Stop page depends on the callout — it is the only way to reach the
/// chevron that pushes the stop — so a regression here silently breaks that screen's entry point.
class StopAnnotationCalloutTests: OBATestCase {

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

    func test_annotationView_withoutDelegate_showsCallout() {
        // The delegate is assigned after init, so the pre-delegate default has to be the
        // conservative one: showing a callout is recoverable, hiding one strands the legacy page.
        #expect(self.makeAnnotationView().canShowCallout)
    }

    func test_annotationView_delegateAllowsCallouts_showsCallout() {
        let view = makeAnnotationView()
        view.delegate = StopAnnotationDelegateStub(showsStopAnnotationCallouts: true)
        #expect(view.canShowCallout)
    }

    func test_annotationView_delegateSuppressesCallouts_hidesCallout() {
        let view = makeAnnotationView()
        view.delegate = StopAnnotationDelegateStub(showsStopAnnotationCallouts: false)
        #expect(!view.canShowCallout)
    }

    func test_annotationView_delegateReassigned_recomputesCallout() {
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

    func test_regionManager_newStopPageEnabled_suppressesCallouts() {
        userDefaults.set(true, forKey: FeatureFlags.useNewStopPageKey)
        #expect(!self.makeRegionManager().showsStopAnnotationCallouts)
    }

    func test_regionManager_newStopPageDisabled_keepsCallouts() {
        userDefaults.set(false, forKey: FeatureFlags.useNewStopPageKey)
        #expect(self.makeRegionManager().showsStopAnnotationCallouts)
    }

    func test_regionManager_flagUnset_suppressesCallouts() {
        // `isNewStopPageEnabled` defaults to true, so an untouched install gets the sheet.
        userDefaults.removeObject(forKey: FeatureFlags.useNewStopPageKey)
        #expect(!self.makeRegionManager().showsStopAnnotationCallouts)
    }

    // MARK: - End-to-end wiring

    /// The delegate stubs above prove the rule; this proves the wiring. `viewFor` is the only
    /// place the real delegate gets attached, so a stop annotation that comes out of it has to
    /// carry the flag's answer.
    @MainActor
    func test_viewFor_flagDisabled_stopAnnotationShowsCallout() throws {
        userDefaults.set(false, forKey: FeatureFlags.useNewStopPageKey)
        let manager = makeRegionManager()
        let stop = try XCTUnwrap(Fixtures.loadSomeStops().first)

        let view = manager.mapView(manager.mapView, viewFor: stop) as? StopAnnotationView

        #expect(view?.canShowCallout == true)
    }

    @MainActor
    func test_viewFor_flagEnabled_stopAnnotationSuppressesCallout() throws {
        userDefaults.set(true, forKey: FeatureFlags.useNewStopPageKey)
        let manager = makeRegionManager()
        let stop = try XCTUnwrap(Fixtures.loadSomeStops().first)

        let view = manager.mapView(manager.mapView, viewFor: stop) as? StopAnnotationView

        #expect(view?.canShowCallout == false)
    }

    // MARK: - Staleness

    /// Turning the flag off in Settings takes effect everywhere that reads it live — the router
    /// starts returning the legacy Stop page again — but an annotation view already on the map
    /// answered the callout question at creation time. Left stale, the legacy page opens on the
    /// first tap with no callout, which is the new page's behavior on the old page's screen.
    @MainActor
    func test_annotationOnMap_flagTurnedOff_refreshRestoresCallout() throws {
        userDefaults.set(true, forKey: FeatureFlags.useNewStopPageKey)
        let manager = makeRegionManager()
        let stop = try XCTUnwrap(Fixtures.loadSomeStops().first)
        let view = try XCTUnwrap(manager.mapView(manager.mapView, viewFor: stop) as? StopAnnotationView)
        #expect(!view.canShowCallout)

        userDefaults.set(false, forKey: FeatureFlags.useNewStopPageKey)
        #expect(!view.canShowCallout)  // still stale...

        view.updateCalloutVisibility()
        #expect(view.canShowCallout)
    }

    /// MapKit's own re-display hook has to pick the change up too, for annotations that scroll
    /// back into view rather than sitting on screen across the flag change.
    @MainActor
    func test_annotationOnMap_flagTurnedOn_prepareForDisplaySuppressesCallout() throws {
        userDefaults.set(false, forKey: FeatureFlags.useNewStopPageKey)
        let manager = makeRegionManager()
        let stop = try XCTUnwrap(Fixtures.loadSomeStops().first)
        let view = try XCTUnwrap(manager.mapView(manager.mapView, viewFor: stop) as? StopAnnotationView)
        #expect(view.canShowCallout)

        userDefaults.set(true, forKey: FeatureFlags.useNewStopPageKey)
        view.prepareForDisplay()

        #expect(!view.canShowCallout)
    }

    @MainActor
    func test_refreshStopAnnotationCallouts_withNoDisplayedAnnotations_isSafe() throws {
        let manager = makeRegionManager()
        manager.mapView.addAnnotation(try XCTUnwrap(Fixtures.loadSomeStops().first))

        manager.refreshStopAnnotationCallouts()
    }
}
