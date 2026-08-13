//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import OBAKitCore

/// Bridges dynamic `ThemeColors` into SwiftUI using the environment's
/// `colorScheme`, so providers like `departureOnTime` resolve against dark
/// traits instead of getting stuck on the light hex (#1255).
enum ThemeSwiftUI {
    static func departureOnTime(_ colorScheme: ColorScheme) -> Color {
        Color(uiColor: ThemeColors.shared.departureOnTime(for: uiStyle(colorScheme)))
    }

    static func departureStatus(_ status: DepartureStatus, _ colorScheme: ColorScheme) -> Color {
        Color(uiColor: status.color(for: uiStyle(colorScheme)))
    }

    private static func uiStyle(_ colorScheme: ColorScheme) -> UIUserInterfaceStyle {
        colorScheme == .dark ? .dark : .light
    }
}
