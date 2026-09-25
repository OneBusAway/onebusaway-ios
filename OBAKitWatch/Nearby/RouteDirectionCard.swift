//
//  RouteDirectionCard.swift
//  OBAKitWatch
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import OBAKitCore

/// A Nearby card: route and headsign only, to orient. Times are one tap away.
struct RouteDirectionCard: View {
    let direction: NearbyRouteDirection

    var body: some View {
        HStack(spacing: 8) {
            RouteDirectionBadge(route: direction.route)
            Text(direction.headsign)
                .font(.headline)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(RouteDirectionBadge.accessibilityLabel(route: direction.route, headsign: direction.headsign))
    }
}

/// The route badge in the agency's colors; shared by the card and the route
/// screen's header so the tap reads as the card opening.
struct RouteDirectionBadge: View {
    let route: Route
    var size: CGFloat = 36

    var body: some View {
        RouteBadgeView(
            routeShortName: route.shortName,
            routeColor: Color(uiColor: route.color ?? ThemeColors.shared.brand),
            routeTextColor: route.textColor.map { Color(uiColor: $0) },
            size: size
        )
    }

    static func accessibilityLabel(route: Route, headsign: String) -> String {
        String(
            format: OBALoc("nearby.card.a11y_fmt", value: "%1$@ to %2$@", comment: "VoiceOver: route short name, headsign. e.g. 'C Line to South Lake Union'"),
            route.shortName, headsign
        )
    }
}
