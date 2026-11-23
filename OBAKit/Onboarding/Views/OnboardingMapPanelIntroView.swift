//
//  OnboardingMapPanelIntroView.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import OBAKitCore

/// Shown once to people who used the app before the map panel became the default
/// layout (see `OnboardingRegistry`), so the move off the tab bar isn't silent: it
/// says where Settings and More went, and how to get the tab bar back.
struct OnboardingMapPanelIntroView: View {
    var progress: (index: Int, total: Int)?
    var advance: () -> Void

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    /// Where Settings and More are depends on the width, the way the map panel
    /// decides it: on iPhone both are rows in the Home list; at regular width
    /// More stays a button on the map.
    private var bodyText: String {
        if HomeTabs.showsTabs(horizontalSizeClass: horizontalSizeClass) {
            OBALoc("onboarding.map_panel_intro.body", value: "The map now fills the screen, with stops, bookmarks, and search in a panel you slide up. Settings and More are at the bottom of the Home list.", comment: "Body of the screen that introduces the app's new map layout, on iPhone. 'Home', 'Settings' and 'More' name items in the app.")
        } else {
            OBALoc("onboarding.map_panel_intro.body_regular", value: "The map now fills the screen, with stops, bookmarks, and search in a panel. Settings is at the bottom of the panel, and More is a button on the map.", comment: "Body of the screen that introduces the app's new map layout, on iPad and other wide screens. 'Settings' and 'More' name items in the app.")
        }
    }

    var body: some View {
        OnboardingScaffold(
            progress: progress,
            // Always NEW, unlike the notifications step: only someone who used the
            // old layout ever sees this one.
            badge: OBALoc("onboarding.map_panel_intro.new_badge", value: "NEW", comment: "Badge on the screen that introduces the app's new map layout to people who used the previous one"),
            title: OBALoc("onboarding.map_panel_intro.title", value: "A new look", comment: "Title of the screen that introduces the app's new map layout to people who used the previous tab bar layout"),
            bodyText: bodyText,
            footnote: OBALoc("onboarding.map_panel_intro.footnote", value: "Prefer the tab bar? Turn on Classic tab bar layout in Settings.", comment: "Footnote of the screen that introduces the app's new map layout. 'Classic tab bar layout' is the name of the switch in Settings and must match its translation (settings_controller.layout_section.classic_tab_bar)."),
            primaryTitle: Strings.continue,
            primaryAction: advance
        ) {
            OnboardingHeroCircle(systemImageName: "map.fill")
                .padding(.vertical, 22)
        }
    }
}

#if DEBUG
#Preview("Map panel intro") {
    OnboardingMapPanelIntroView(advance: {})
}
#endif
