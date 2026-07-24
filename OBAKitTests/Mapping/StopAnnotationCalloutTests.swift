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
import Nimble

/// Covers the gate that decides whether tapping a stop annotation shows a callout or opens the
/// stop outright. The legacy Stop page depends on the callout — it is the only way to reach the
/// chevron that pushes the stop — so a regression here silently breaks that screen's entry point.
class StopAnnotationCalloutTests: OBATestCase {

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
        expect(self.makeAnnotationView().canShowCallout).to(beTrue())
    }

    func test_annotationView_delegateAllowsCallouts_showsCallout() {
        let view = makeAnnotationView()
        view.delegate = StopAnnotationDelegateStub(showsStopAnnotationCallouts: true)
        expect(view.canShowCallout).to(beTrue())
    }

    func test_annotationView_delegateSuppressesCallouts_hidesCallout() {
        let view = makeAnnotationView()
        view.delegate = StopAnnotationDelegateStub(showsStopAnnotationCallouts: false)
        expect(view.canShowCallout).to(beFalse())
    }

    func test_annotationView_delegateReassigned_recomputesCallout() {
        // Annotation views are recycled and `viewFor` reassigns the delegate on each reuse.
        let view = makeAnnotationView()
        view.delegate = StopAnnotationDelegateStub(showsStopAnnotationCallouts: false)
        view.delegate = StopAnnotationDelegateStub(showsStopAnnotationCallouts: true)
        expect(view.canShowCallout).to(beTrue())
    }

    // MARK: - MapRegionManager

    private func makeRegionManager() -> MapRegionManager {
        let queue = OperationQueue()
        let application = buildApplication(queue: queue, dataLoader: MockDataLoader(testName: name))
        return MapRegionManager(application: application)
    }

    func test_regionManager_newStopPageEnabled_suppressesCallouts() {
        userDefaults.set(true, forKey: FeatureFlags.useNewStopPageKey)
        expect(self.makeRegionManager().showsStopAnnotationCallouts).to(beFalse())
    }

    func test_regionManager_newStopPageDisabled_keepsCallouts() {
        userDefaults.set(false, forKey: FeatureFlags.useNewStopPageKey)
        expect(self.makeRegionManager().showsStopAnnotationCallouts).to(beTrue())
    }

    func test_regionManager_flagUnset_suppressesCallouts() {
        // `isNewStopPageEnabled` defaults to true, so an untouched install gets the sheet.
        userDefaults.removeObject(forKey: FeatureFlags.useNewStopPageKey)
        expect(self.makeRegionManager().showsStopAnnotationCallouts).to(beFalse())
    }
}
