//
//  CurrentLocationButton.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import OBAKitCore

/// Floating "center on my location" pill rendered on the bottom-trailing cluster
/// of `MapPanelRootView`. Hidden entirely when location isn't authorized,
/// matching the UIKit `MapViewController.locationButton.isHidden` behavior.
struct CurrentLocationButton: View {
    let isVisible: Bool
    let onTap: () -> Void

    var body: some View {
        if isVisible {
            Button(action: onTap) {
                Image(uiImage: Icons.nearMe)
                    .renderingMode(.template)
                    .frame(width: 40, height: 40)
                    .contentShape(Circle())
            }
            .liquidGlassButtonStyle(borderShape: .circle, fallbackShape: Circle())
            .accessibilityLabel(Text(OBALoc(
                "map_controller.center_user_location",
                value: "Center map on current location",
                comment: "Map controller for centering the map on the user's current location."
            )))
        }
    }
}
