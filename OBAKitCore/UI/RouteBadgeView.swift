//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI

/// Rounded-square route identity badge. Public so the widget extension can use it.
public struct RouteBadgeView: View {
    public let routeShortName: String
    public let routeColor: Color
    public var size: CGFloat = 44

    @ScaledMetric(relativeTo: .body) private var scale: CGFloat = 1

    public init(routeShortName: String, routeColor: Color, size: CGFloat = 44) {
        self.routeShortName = routeShortName
        self.routeColor = routeColor
        self.size = size
    }

    public var body: some View {
        Text(routeShortName)
            .font(.system(size: (routeShortName.count <= 2 ? 18 : 13) * scale, weight: .heavy))
            .monospacedDigit()
            .foregroundStyle(.white)
            .minimumScaleFactor(0.6)
            .lineLimit(1)
            .frame(width: size * scale, height: size * scale)
            .background(routeColor.gradient, in: RoundedRectangle(cornerRadius: size * scale * 0.28, style: .continuous))
            .accessibilityHidden(true)
    }
}
