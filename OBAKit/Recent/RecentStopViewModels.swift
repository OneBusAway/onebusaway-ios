//
//  RecentStopViewModels.swift
//  OBAKit
//
//  Created by Alan Chu on 11/3/20.
//

import OBAKitCore

/// A view model for use with OBAListView for displaying basic stop details.
///
/// This model uses a default content configuration, there is no need to register this
/// item with OBAListView before use.
struct StopViewModel: OBAListViewItem {
    let name: String
    let subtitle: String?

    let id: Stop.ID
    let routeType: Route.RouteType

    // Hide icon if there is only one type of route in the list
    var configuration: OBAListViewItemConfiguration {
        let transportIcon = Icons.transportIcon(from: routeType)
        var config = OBAListRowConfiguration(
            image: transportIcon,
            text: .string(name),
            secondaryText: .string(subtitle),
            appearance: .subtitle,
            accessoryType: .disclosureIndicator)
        config.imageConfig.tintColor = .label
        config.imageConfig.maximumSize = CGSize(width: 24, height: 24)

        return .custom(config)
    }

    let onSelectAction: OBAListViewAction<StopViewModel>?
    let onDeleteAction: OBAListViewAction<StopViewModel>?

    init(withStop stop: Stop,
         showDirectionInTitle: Bool = false,
         onSelect selectAction: OBAListViewAction<StopViewModel>?,
         onDelete deleteAction: OBAListViewAction<StopViewModel>?) {

        self.name = showDirectionInTitle ? stop.nameWithLocalizedDirectionAbbreviation : stop.name
        self.subtitle = stop.subtitle
        self.routeType = stop.prioritizedRouteTypeForDisplay

        self.id = stop.id
        self.onSelectAction = selectAction
        self.onDeleteAction = deleteAction
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: StopViewModel, rhs: StopViewModel) -> Bool {
        return lhs.id == rhs.id
    }
}

extension RecentStopsViewController {
    struct AlarmViewModel: OBAListViewItem {
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
