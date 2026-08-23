//
//  StopPageAccessibilityCopy.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import OBAKitCore

/// Spoken identity for an upcoming stop-page row. The minutes badge is
/// "5m" either way; first/layover stops are `.departing` and every other
/// stop is `.arriving`. VoiceOver used to say "departs" for both (#447).
enum StopPageAccessibilityCopy {
    static func upcomingIdentity(
        routeShortName: String,
        headsign: String,
        minutes: Int,
        arrivalDepartureStatus: ArrivalDepartureStatus,
        adherence: String
    ) -> String {
        let fmt: String
        switch arrivalDepartureStatus {
        case .arriving:
            fmt = OBALoc(
                "stop_page.row.a11y_arrives_fmt",
                value: "Route %@ to %@, arrives in %d minutes, %@",
                comment: "VoiceOver for a stop-page row whose vehicle is arriving at this stop. Route, headsign, minutes, adherence."
            )
        case .departing:
            fmt = OBALoc(
                "stop_page.row.a11y_fmt",
                value: "Route %@ to %@, departs in %d minutes, %@",
                comment: "VoiceOver for a stop-page row whose vehicle is departing this stop (first stop or layover). Route, headsign, minutes, adherence."
            )
        }
        return String(format: fmt, routeShortName, headsign, minutes, adherence)
    }

    /// VoiceOver for a grouped route card. The next trip is arriving or
    /// departing; saying "next departure" for both is the same #447 gap.
    static func groupedCardIdentity(
        routeShortName: String,
        headsign: String,
        minutes: Int,
        arrivalDepartureStatus: ArrivalDepartureStatus,
        adherence: String,
        moreCount: Int
    ) -> String {
        let fmt: String
        switch arrivalDepartureStatus {
        case .arriving:
            fmt = OBALoc(
                "stop_page.grouped.a11y_arrives_fmt",
                value: "Route %@ to %@, next arrival in %d minutes, %@. %d more departures loaded.",
                comment: "VoiceOver for a grouped route card whose next vehicle is arriving at this stop."
            )
        case .departing:
            fmt = OBALoc(
                "stop_page.grouped.a11y_fmt",
                value: "Route %@ to %@, next departure in %d minutes, %@. %d more departures loaded.",
                comment: "VoiceOver for a grouped route card whose next vehicle is departing this stop (first stop or layover)."
            )
        }
        return String(format: fmt, routeShortName, headsign, minutes, adherence, moreCount)
    }
}
