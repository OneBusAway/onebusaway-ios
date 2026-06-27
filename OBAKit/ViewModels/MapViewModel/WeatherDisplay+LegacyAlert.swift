//
//  WeatherDisplay+LegacyAlert.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import OBAKitCore

// MARK: - Legacy Alert (transitional)
//
// `MapViewController.showWeather()` renders a UIAlertController when the
// `OBAUseMapPanelExperience` flag is OFF. The SwiftUI panel surface (the
// `WeatherDetailPopup` card) never reads this content. Keeping the formatting
// here — out of the primary `WeatherDisplay.init` — means the SwiftUI path
// doesn't pay three `String(format:)` calls per refresh, and when the
// experience flag is finally removed the cleanup is a single-file delete:
// drop this file and the `todaySummary` field that supports it.

extension WeatherDisplay {

    /// Pre-rendered content for the legacy `UIAlertController`. Derived from
    /// the same `Header` / `Stats` slices the SwiftUI card consumes, so the
    /// two surfaces stay in lockstep on copy.
    struct LegacyAlert: Equatable {
        let title: String
        let message: String
    }

    /// Computed (not stored) so the SwiftUI panel path doesn't pay the format
    /// cost. Cheap enough on the UIKit side — it's invoked once per
    /// alert-presentation, not per SwiftUI body re-evaluation.
    var legacyAlert: LegacyAlert {
        let tempLine = String(
            format: OBALoc(
                "weather.alert.temp_line_format",
                value: "Temp: %@ (Feels like %@)",
                comment: "Legacy alert line. First %@ is current temperature, second is feels-like temperature."
            ),
            header.currentTemp, stats.feelsLikeText
        )
        let windLine = String(
            format: OBALoc(
                "weather.alert.wind_line_format",
                value: "Wind: %@",
                comment: "Legacy alert line. %@ is the formatted wind speed."
            ),
            stats.windText
        )
        let precipLine = String(
            format: OBALoc(
                "weather.alert.precip_line_format",
                value: "Precipitation: %@ chance",
                comment: "Legacy alert line. %@ is the chance-of-precipitation percentage."
            ),
            stats.precipText
        )
        return LegacyAlert(title: todaySummary, message: "\(tempLine)\n\(windLine)\n\(precipLine)")
    }
}
