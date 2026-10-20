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

    /// The UIKit map's wider stop load under VoiceOver.
    static let voiceOverLoadDataRegionFudgeFactor = 1.5
}

struct MapPanelVoiceOverModifier: ViewModifier {
    let application: Application
    @ObservedObject var coordinator: SheetCoordinator<AppSheetRoute>
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
            ? MapPanelVoiceOver.voiceOverLoadDataRegionFudgeFactor
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
        let title = OBALoc("floating_panel.controller.full_sheet_voiceover_change_alert.title", value: "Voiceover detected", comment: "")
        let message = OBALoc("floating_panel.controller.full_sheet_voiceover_change_alert.message", value: "The sheet will automatically expand when VoiceOver is turned on. To disable this behavior, visit the Settings page.", comment: "")
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(.dismissAction)
        host.present(alert, animated: true)
    }
}
