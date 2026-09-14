//
//  TimeZone+ScheduleBadge.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

extension TimeZone {

    /// Short badge to show next to a clock time when this zone's offset differs
    /// from `device`.
    ///
    /// Never uses `NameStyle.shortGeneric`. That style yields `PT`/`ET` in North
    /// America and long names everywhere else (`Poland Time`, `United Kingdom
    /// Time`) — which is why #1102 was closed. Prefer a 2–5 letter abbreviation
    /// (`PST`, `CET`, `IST`); otherwise a `GMT±H` / `GMT±H:MM` offset.
    ///
    /// Returns `nil` when the offsets match, so a rider already in the region
    /// does not see a redundant `PST`.
    public func scheduleBadge(at date: Date, versus device: TimeZone) -> String? {
        guard secondsFromGMT(for: date) != device.secondsFromGMT(for: date) else {
            return nil
        }

        if let abbreviation = abbreviation(for: date), Self.isUsableAbbreviation(abbreviation) {
            return abbreviation
        }

        return Self.gmtOffsetLabel(secondsFromGMT: secondsFromGMT(for: date))
    }

    /// The most common resolvable IANA identifier. An even split picks the
    /// lexicographically first identifier so the winner does not change between
    /// launches. Invalid strings are skipped.
    public static func preferredScheduleTimeZone(identifiers: [String]) -> TimeZone? {
        let resolved = identifiers.compactMap { TimeZone(identifier: $0) }
        guard !resolved.isEmpty else { return nil }

        let counts = Dictionary(grouping: resolved, by: \.identifier).mapValues(\.count)
        guard let maxCount = counts.values.max() else { return nil }
        let identifier = counts
            .filter { $0.value == maxCount }
            .keys
            .sorted()
            .first
        return identifier.flatMap { TimeZone(identifier: $0) }
    }

    /// `PST`, `CEST`, `IST` — not `GMT+9`, not `Poland Time`.
    static func isUsableAbbreviation(_ value: String) -> Bool {
        (2...5).contains(value.count) && value.unicodeScalars.allSatisfy { CharacterSet.uppercaseLetters.contains($0) }
    }

    static func gmtOffsetLabel(secondsFromGMT: Int) -> String {
        let sign = secondsFromGMT >= 0 ? "+" : "-"
        let absolute = abs(secondsFromGMT)
        let hours = absolute / 3600
        let minutes = (absolute % 3600) / 60
        if minutes == 0 {
            return String(
                format: OBALoc(
                    "timezone.gmt_offset_hours_fmt",
                    value: "GMT%@%d",
                    comment: "GMT offset with whole hours, e.g. GMT+5 or GMT-8. First argument is + or -. Second is the hour count."
                ),
                sign,
                hours
            )
        }
        return String(
            format: OBALoc(
                "timezone.gmt_offset_hours_minutes_fmt",
                value: "GMT%@%d:%02d",
                comment: "GMT offset with hours and minutes, e.g. GMT+5:30. Arguments are sign, hours, and zero-padded minutes."
            ),
            sign,
            hours,
            minutes
        )
    }
}
