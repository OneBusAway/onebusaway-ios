//
//  MyTripButton.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import OBAKitCore

/// Floating bus pill rendered over `MapPanelRootView`'s map. Always visible —
/// the UIKit `MapViewController.myTripButton` is unconditional too.
struct MyTripButton: View {
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Image(uiImage: Icons.busButton)
                .renderingMode(.template)
                .frame(width: 40, height: 40)
                .contentShape(Circle())
        }
        .liquidGlassButtonStyle(borderShape: .circle, fallbackShape: Circle())
        .accessibilityLabel(Text(OBALoc(
            "map_controller.my_trip_button",
            value: "My Trip",
            comment: "Accessibility label for the My Trip button on the map toolbar."
        )))
    }
}
