//
//  MapPanelVoiceOver.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import UIKit
import OBAKitCore

/// What the map panel does for VoiceOver, as `MapViewController.updateVoiceover()`
/// does on the UIKit map: raises the home sheet off its search-bar-only detent,
/// says so once, and loads stops a little wider around the map.
///
/// Without it a VoiceOver rider landed on a 75 pt sheet holding a search field,
/// over a map whose pins VoiceOver reads one by one.
enum MapPanelVoiceOver {
    /// Where the home sheet goes, or nil to leave it. Only off its collapsed
    /// detent, so a sheet the rider moved stays where they put it.
    static func homeDetent(
        isVoiceOverRunning: Bool,
        expandsSheet: Bool,
        currentDetent: PresentationDetent
    ) -> PresentationDetent? {
        guard isVoiceOverRunning, expandsSheet,
              currentDetent == .height(AppSheetRoute.homeCollapsedHeight) else { return nil }
        return .medium
    }
}

struct MapPanelVoiceOverModifier: ViewModifier {
    let application: Application
    /// Read when VoiceOver changes, not rendered from, so not observed.
    let coordinator: SheetCoordinator<AppSheetRoute>
    let presentingController: () -> UIViewController?

    func body(content: Content) -> some View {
        content
            .onAppear(perform: update)
            .onReceive(NotificationCenter.default.publisher(for: UIAccessibility.voiceOverStatusDidChangeNotification)) { _ in
                update()
            }
    }

    private func update() {
        let defaults = application.userDefaults
        OBAFloatingPanelController.registerVoiceOverDefaults(in: defaults)
        let isRunning = UIAccessibility.isVoiceOverRunning

        application.mapRegionManager.preferredLoadDataRegionFudgeFactor = isRunning
            ? MapRegionManager.VoiceOverLoadDataRegionFudgeFactor
            : MapRegionManager.DefaultLoadDataRegionFudgeFactor

        guard coordinator.currentRoute == .home,
              let detent = MapPanelVoiceOver.homeDetent(
                isVoiceOverRunning: isRunning,
                expandsSheet: defaults.bool(forKey: OBAFloatingPanelController.AlwaysShowFullSheetOnVoiceoverUserDefaultsKey),
                currentDetent: coordinator.currentDetent
              ) else { return }
        coordinator.currentDetent = detent

        let seenKey = OBAFloatingPanelController.UserHasSeenFullSheetVoiceoverChangeUserDefaultsKey
        guard !defaults.bool(forKey: seenKey), let host = presentingController() else { return }
        defaults.set(true, forKey: seenKey)
        host.present(OBAFloatingPanelController.fullSheetVoiceoverAlert(), animated: true)
    }
}
