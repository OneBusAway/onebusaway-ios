//
//  RecentStopRowItems.swift
//  OBAKit
//
//  Created by Alan Chu on 11/3/20.
//

import OBAKitCore

/// A view model for use with OBAListView for displaying basic stop details.
///
/// This model uses a default content configuration, there is no need to register this
/// item with OBAListView before use.
nonisolated struct StopRowItem: OBAListViewItem {
    let name: String
    let subtitle: String?

    let id: UUID = UUID()
    let stopID: Stop.ID
    let routeType: Route.RouteType

    var configuration: OBAListViewItemConfiguration {
        var config = OBAListRowConfiguration(
            image: Icons.squircleTransportIcon(for: routeType),
            text: .attributed(styledTitle),
            secondaryText: .attributed(styledSubtitle),
            appearance: .subtitle,
            accessoryType: .disclosureIndicator)
        // The squircle icon is pre-rendered with its own colors; don't re-tint.
        config.imageConfig.tintColor = nil
        config.imageConfig.maximumSize = CGSize(width: Icons.squircleIconSize, height: Icons.squircleIconSize)

        return .custom(config)
    }

    private var styledTitle: NSAttributedString {
        NSAttributedString(string: name, attributes: [
            .font: UIFont.preferredFont(forTextStyle: .title3).bold,
            .foregroundColor: UIColor.label
        ])
    }

    private var styledSubtitle: NSAttributedString? {
        guard let subtitle else { return nil }
        return NSAttributedString(string: subtitle, attributes: [
            .font: UIFont.preferredFont(forTextStyle: .body),
            .foregroundColor: UIColor.label
        ])
    }

    let onSelectAction: OBAListViewAction<StopRowItem>?
    let onDeleteAction: OBAListViewAction<StopRowItem>?

    init(withStop stop: Stop,
         showDirectionInTitle: Bool = false,
         onSelect selectAction: OBAListViewAction<StopRowItem>?,
         onDelete deleteAction: OBAListViewAction<StopRowItem>?) {

        self.name = showDirectionInTitle ? stop.nameWithLocalizedDirectionAbbreviation : stop.name
        self.subtitle = stop.subtitle
        self.routeType = stop.prioritizedRouteTypeForDisplay

        self.stopID = stop.id
        self.onSelectAction = selectAction
        self.onDeleteAction = deleteAction
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(stopID)
        hasher.combine(name)
        hasher.combine(routeType)
    }

    static func == (lhs: StopRowItem, rhs: StopRowItem) -> Bool {
        return lhs.id == rhs.id &&
            lhs.stopID == rhs.stopID &&
            lhs.name == rhs.name &&
            lhs.routeType == rhs.routeType
    }
}

extension RecentStopsViewController {
    nonisolated struct AlarmViewModel: OBAListViewItem {
        let alarm: Alarm
        let deepLink: ArrivalDepartureDeepLink

        let title: String

        var id: URL { alarm.url }

        var configuration: OBAListViewItemConfiguration {
            return .custom(OBAListRowConfiguration(
                            text: .string(title),
                            appearance: .subtitle,
                            accessoryType: .disclosureIndicator))
        }

        let onSelectAction: OBAListViewAction<AlarmViewModel>?
        let onDeleteAction: OBAListViewAction<AlarmViewModel>?

        init?(withAlarm alarm: Alarm,
              onSelect selectAction: OBAListViewAction<AlarmViewModel>?,
              onDelete deleteAction: OBAListViewAction<AlarmViewModel>?) {
            guard let deepLink = alarm.deepLink else { return nil }
            self.alarm = alarm
            self.deepLink = deepLink
            self.title = deepLink.title

            self.onSelectAction = selectAction
            self.onDeleteAction = deleteAction
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(id)
            hasher.combine(title)
            alarm.hash(into: &hasher)
            deepLink.hash(into: &hasher)
        }

        static func == (lhs: AlarmViewModel, rhs: AlarmViewModel) -> Bool {
            return lhs.alarm.isEqual(rhs.alarm) &&
                lhs.deepLink.isEqual(rhs.deepLink) &&
                lhs.title == rhs.title
        }
    }
}
