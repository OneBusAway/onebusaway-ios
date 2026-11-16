//
//  HomeSettingsSection.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import OBAKitCore

/// A row in the home sheet's Settings and More section, the last on Home: the
/// ways into the app's options, which nothing else on the panel leads to.
enum HomeSettingsItem: String, Hashable, Identifiable, CaseIterable {
    /// The Map sheet: basemap, routes on the map, and the map's layers.
    case customizeMap
    /// The app's settings, presented as the classic More tab presents them.
    case settings
    /// The classic app's More tab: donations, regions, feedback, help.
    case more

    /// The rows to show, in order.
    ///
    /// - Parameter offersMore: Whether More belongs here. On iPhone only, where
    ///   nothing else on the panel leads there; regular width keeps its More
    ///   button on the map.
    static func items(offersMore: Bool) -> [HomeSettingsItem] {
        offersMore ? allCases : allCases.filter { $0 != .more }
    }

    var id: String { rawValue }

    var title: String {
        switch self {
        case .customizeMap:
            OBALoc("home_sheet.settings.customize_map.title", value: "Customize Map", comment: "Title of a row on the map panel's home sheet that opens the map display options: basemap, routes and layers.")
        case .settings:
            Strings.settings
        case .more:
            Strings.moreTabTitle
        }
    }

    /// - Parameter offersDonations: Whether the More screen has a donate
    ///   option. It doesn't in an app without donations, so the More row
    ///   mustn't promise one.
    func subtitle(offersDonations: Bool) -> String {
        switch self {
        case .customizeMap:
            OBALoc("home_sheet.settings.customize_map.subtitle", value: "Change map display options", comment: "Subtitle of the Customize Map row on the map panel's home sheet.")
        case .settings:
            OBALoc("home_sheet.settings.settings.subtitle", value: "Change app settings", comment: "Subtitle of the Settings row on the map panel's home sheet.")
        case .more:
            if offersDonations {
                OBALoc("home_sheet.settings.more.subtitle", value: "Donate, Change Region, Give Feedback, and more", comment: "Subtitle of the More row on the map panel's home sheet, listing some of what the More screen holds.")
            } else {
                OBALoc("home_sheet.settings.more.subtitle_no_donations", value: "Change Region, Give Feedback, and more", comment: "Subtitle of the More row on the map panel's home sheet, in an app without donations, listing some of what the More screen holds.")
            }
        }
    }

    var systemImage: String {
        switch self {
        case .customizeMap: "map"
        case .settings: "gearshape"
        case .more: "ellipsis.circle"
        }
    }
}

/// One row of the Settings and More section: icon, title over subtitle, and a
/// chevron, since each opens another screen.
struct HomeSettingsRow: View {
    let item: HomeSettingsItem
    let offersDonations: Bool
    let action: () -> Void

    @ScaledMetric(relativeTo: .body) private var iconWidth: CGFloat = 28

    /// Same chevron as `HomeStopRow`'s, the other rows on Home that open a page.
    private let brandColor = Color(uiColor: ThemeColors.shared.brand)

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: item.systemImage)
                    .font(.title3)
                    .foregroundStyle(Color(uiColor: ThemeColors.shared.brandAccent))
                    .frame(width: iconWidth)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .foregroundStyle(Color(uiColor: .label))
                    Text(item.subtitle(offersDonations: offersDonations))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.forward")
                    .font(.footnote)
                    .fontWeight(.semibold)
                    .foregroundStyle(brandColor)
                    .accessibilityHidden(true)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
#Preview {
    List {
        Section {
            ForEach(HomeSettingsItem.allCases) { item in
                HomeSettingsRow(item: item, offersDonations: true) {}
            }
        } header: {
            HomeSectionTitle(title: Strings.settingsAndMore)
        }
    }
}
#endif
