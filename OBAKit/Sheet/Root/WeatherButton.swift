//
//  WeatherButton.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import OBAKitCore

/// Floating temperature pill rendered over `MapPanelRootView`'s map. Hidden when
/// the forecast is unavailable so the overlay reserves no space.
struct WeatherButton: View {
    let display: WeatherDisplay?
    let onTap: (WeatherDisplay) -> Void

    var body: some View {
        if let display {
            Button {
                onTap(display)
            } label: {
                Text(display.buttonTitle)
                    .font(.body.bold())
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .contentShape(Capsule())
            }
            .regularGlassEffectIfAvailable()
            .buttonStyle(.plain)
            .accessibilityLabel(
                Text(OBALoc(
                    "map_controller.show_weather_button",
                    value: "Show Weather Forecast",
                    comment: "Accessibility label for a button that provides the current forecast"
                ))
            )
            .accessibilityValue(Text(display.buttonTitle))
        }
    }
}
