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
///
/// These formats carry a minute count and resolve through `Localizable.stringsdict`.
/// The locale has to be passed to `String(format:locale:)` explicitly: the no-locale
/// overload resolves `%#@count@` against the *root* plural rule, so only `one` and
/// `other` are ever reachable and a Polish rider hears "5 minuty" instead of
/// "5 minut". `locale` is injectable so tests can exercise a locale whose categories
/// differ from the root's.
enum StopPageAccessibilityCopy {
    /// The departures after a route card's next one, as its chips show them:
    /// "Arrives in 12 min, live tracking, 3 min late." for each. `nil` when there
    /// are none.
    static func followingDepartures(
        _ departures: [ArrivalDeparture],
        formatters: Formatters,
        status: (ArrivalDeparture) -> DepartureStatus
    ) -> String? {
        guard !departures.isEmpty else { return nil }
        return departures.map { departure in
            let time = formatters.explanationForArrivalDeparture(
                tempuraState: departure.temporalState,
                arrivalDepartureStatus: departure.arrivalDepartureStatus,
                arrivalDepartureMinutes: departure.arrivalDepartureMinutes
            )
            return time + ", " + status(departure).accessibilityStatusDescription + "."
        }
        .joined(separator: " ")
    }

    /// The pushed header's heading. The label is what the map pin says (name,
    /// direction, "Routes: …", stop ID) so the Headings rotor lists the stop by
    /// name. The "Updated: …" line is the value: it changes every few seconds,
    /// and as the start of the label it read before the stop's name.
    static func header(stop: Stop, statusText: String) -> (label: String, value: String?) {
        (Formatters.formattedAccessibilityLabel(stop: stop), statusText.isEmpty ? nil : statusText)
    }

    static func upcomingIdentity(
        routeShortName: String,
        headsign: String,
        minutes: Int,
        arrivalDepartureStatus: ArrivalDepartureStatus,
        adherence: String,
        locale: Locale = .current
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
        return String(format: fmt, locale: locale, routeShortName, headsign, minutes, adherence)
    }

    /// VoiceOver for a grouped route card. The next trip is arriving or
    /// departing; saying "next departure" for both is the same #447 gap.
    static func groupedCardIdentity(
        routeShortName: String,
        headsign: String,
        minutes: Int,
        arrivalDepartureStatus: ArrivalDepartureStatus,
        adherence: String,
        moreCount: Int,
        locale: Locale = .current
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
        return String(format: fmt, locale: locale, routeShortName, headsign, minutes, adherence, moreCount)
    }
}
