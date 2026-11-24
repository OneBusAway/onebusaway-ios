//
//  Formatters+TripBookmark.swift
//  OBAKit
//
//  Created by Alan Chu on 6/11/20.
//

import OBAKitCore

extension Formatters {
    /// Generates a localized label ideal for Voiceover describing the provided `BookmarkRowViewModel`.
    /// As the method name suggests, this value is best used for the `UIAccessibility.accessibilityLabel` property.
    /// - parameter bookmarkArrivalData: The `BookmarkRowViewModel` to describe.
    /// - returns: A localized Voiceover label describing the provided `BookmarkRowViewModel`.
    func accessibilityLabel(for bookmarkArrivalData: BookmarkRowViewModel) -> String {
        let stringFormat: String
        if bookmarkArrivalData.isTripBookmark {
            stringFormat = bookmarkArrivalData.isFavorite
                ? OBALoc("voiceover.bookmarkarrivaldata.label.favoriteroutebookmark_fmt", value: "Favorite Route Bookmark, %@", comment: "Format string describing a favorite route (or trip) bookmark with a placeholder for the bookmark's name.")
                : OBALoc("voiceover.bookmarkarrivaldata.label.routebookmark_fmt", value: "Route Bookmark, %@", comment: "Format string describing a normal route (or trip) bookmark with a placeholder for the bookmark's name.")
        } else {
            stringFormat = OBALoc("voiceover.bookmarkarrivaldata.label.stopbookmark_fmt", value: "Stop Bookmark, %@", comment: "Format string describing a stop bookmark with a placeholder for the bookmark's name.")
        }

        return String(format: stringFormat, bookmarkArrivalData.name)
    }

    /// Generates a localized string value ideal for Voiceover describing the provided `BookmarkRowViewModel`.
    /// As the method name suggests, this value is best used for the `UIAccessibility.accessibilityValue` property.
    /// - parameter bookmarkArrivalData: The `BookmarkRowViewModel` to describe.
    /// - returns: A localized Voiceover value describing the provided `BookmarkRowViewModel`.
    func accessibilityValue(for bookmarkArrivalData: BookmarkRowViewModel) -> String? {
        guard bookmarkArrivalData.isTripBookmark else { return nil }

        // Offline, the departures are saved ones, so say so before reading
        // them out. With none left to read, that's all there is to say: "No
        // upcoming departures" would claim more than saved data can.
        let savedText = savedArrivalsText(for: bookmarkArrivalData)
        if let savedText, let timetableText = scheduledDeparturesAccessibilityValue(for: bookmarkArrivalData) {
            return savedText + ". " + timetableText
        }
        if let savedText, bookmarkArrivalData.upcomingArrivalDepartures.isEmpty {
            return savedText + "."
        }

        guard var value = departuresAccessibilityValue(for: bookmarkArrivalData) else {
            return nil
        }

        if let savedText {
            value = savedText + ". " + value
        }

        // Spoken as its own sentence after the departures, matching the card,
        // where the arrival line sits below the departure line (#1080).
        if let destinationText = destinationText(for: bookmarkArrivalData, spoken: true) {
            value += " " + destinationText + "."
        }

        return value
    }

    /// The line a trip bookmark's card shows while its departures are saved
    /// ones because the device is offline, e.g. "Offline, saved 8:42 AM".
    /// `nil` while the departures are live.
    func savedArrivalsText(for row: BookmarkRowViewModel) -> String? {
        guard let savedAt = row.savedArrivalsDate else { return nil }
        if row.isShowingTimetable {
            return OBALoc("bookmark_card.offline_timetable", value: "Offline, scheduled times", comment: "Shown on a bookmark card when the device is offline, the departures the app saved have all left, and the times shown come from the stop's saved timetable instead.")
        }
        let format = OBALoc("bookmark_card.offline_saved_fmt", value: "Offline, saved %@", comment: "Shown on a bookmark card when the device is offline and the departures shown are the last ones the app saved. The placeholder is the time they were saved, e.g. 'Offline, saved 8:42 AM'.")
        return String(format: format, timeFormatter.string(from: savedAt))
    }

    /// The line a destination bookmark's card shows about arriving at its
    /// destination, e.g. "Arrives 5:41 PM · Pine St". The time leads so that a
    /// long stop name truncates instead of the time. `spoken` swaps that layout,
    /// whose "·" is meaningless to VoiceOver, for a sentence: "Arrives Pine St
    /// at 5:41 PM". `nil` for bookmarks
    /// without a destination, or while there are no departures to describe.
    func destinationText(for row: BookmarkRowViewModel, spoken: Bool = false) -> String? {
        guard let name = row.destinationStopName, let status = row.destinationStatus else { return nil }

        switch status {
        case .loading:
            let format = OBALoc("bookmark_card.destination.loading_fmt", value: "Loading arrival at %@…", comment: "Shown on a trip bookmark card while the arrival time at the bookmark's destination stop is loading. The placeholder is the destination stop's name.")
            return String(format: format, name)
        case .arrives(let arrival):
            let time = timeFormatter.string(from: arrival.arrivalDate)
            let format: String
            switch (arrival.isRealTime, spoken) {
            case (true, false):
                format = OBALoc("bookmark_card.destination.arrives_fmt", value: "Arrives %2$@ · %1$@", comment: "Shown on a trip bookmark card with the estimated arrival time at the bookmark's destination stop, based on real-time data. 1st placeholder is the destination stop's name, 2nd is the time, e.g. 'Arrives 5:41 PM · Pine St'.")
            case (false, false):
                format = OBALoc("bookmark_card.destination.arrives_scheduled_fmt", value: "Arrives %2$@ (scheduled) · %1$@", comment: "Shown on a trip bookmark card with the scheduled arrival time at the bookmark's destination stop, when no real-time data is available. 1st placeholder is the destination stop's name, 2nd is the time.")
            case (true, true):
                format = OBALoc("bookmark_card.destination.arrives_spoken_fmt", value: "Arrives %1$@ at %2$@", comment: "VoiceOver sentence for a trip bookmark's estimated arrival time at its destination stop, based on real-time data. 1st placeholder is the destination stop's name, 2nd is the time, e.g. 'Arrives Pine St at 5:41 PM'.")
            case (false, true):
                format = OBALoc("bookmark_card.destination.arrives_scheduled_spoken_fmt", value: "Arrives %1$@ at %2$@ (scheduled)", comment: "VoiceOver sentence for a trip bookmark's scheduled arrival time at its destination stop, when no real-time data is available. 1st placeholder is the destination stop's name, 2nd is the time.")
            }
            return String(format: format, name, time)
        case .notServed:
            let format = OBALoc("bookmark_card.destination.not_served_fmt", value: "Upcoming trips don't stop at %@", comment: "Shown on a trip bookmark card when none of the upcoming trips on the route stop at the bookmark's destination stop. The placeholder is the destination stop's name.")
            return String(format: format, name)
        }
    }

    /// The timetable part of `accessibilityValue(for:)`, e.g. "scheduled to
    /// depart in 6 minutes at 8:55 PM. Following two departures in 21 minutes
    /// and 36 minutes."; `nil` when the card isn't showing the timetable.
    private func scheduledDeparturesAccessibilityValue(for row: BookmarkRowViewModel) -> String? {
        let timetable = row.upcomingScheduledDepartures
        guard let first = timetable.first else { return nil }

        let firstMinutes = max(0, first.minutes)
        var value = accessibilityValueForArrivalDeparture(
            arrivalDepartureDate: first.date,
            arrivalDepartureMinutes: firstMinutes,
            arrivalDepartureStatus: .departing,
            temporalState: firstMinutes == 0 ? .present : .future,
            scheduleStatus: .unknown
        )

        let following = timetable.dropFirst().prefix(2).map { max(0, $0.minutes) }
        if following.count == 2 {
            let format = OBALoc("voiceover.bookmarkarrivaldata.value.followingtwodepartures_fmt", value: "Following two departures in %d minutes and %d minutes.", comment: "Voiceover text describing the two additional departures in the near-future, regardless of realtime data availability.")
            value += " " + String(format: format, following[0], following[1])
        } else if let next = following.first {
            let format = OBALoc("voiceover.bookmarkarrivaldata.value.followingonedeparture_fmt", value: "Following departure in %d minutes.", comment: "Voiceover text describing the one additional departure in the near-future, regardless of realtime data availability.")
            value += " " + String(format: format, next)
        }
        return value
    }

    /// The departures part of `accessibilityValue(for:)`.
    private func departuresAccessibilityValue(for bookmarkArrivalData: BookmarkRowViewModel) -> String? {
        let arrivalDepartures = bookmarkArrivalData.upcomingArrivalDepartures
        guard let firstArrivalDeparture = arrivalDepartures.first else {
            return OBALoc("voiceover.bookmarkarrivaldata.value.noupcomingdepartures_fmt", value: "No upcoming departures", comment: "Voiceover text describing no departures in the near-future.")
        }

        var value = self.accessibilityValue(for: firstArrivalDeparture)

        // The visual card renders the corrected time with the schedule struck
        // through (`DepartureTimeText`); a strikethrough is inaudible, so the
        // correction is carried here in words. Only the corrected case is
        // spoken: the base value above already names the expected clock time,
        // so the plain "at %@" clause would merely repeat it. Appended as its
        // own sentence — the base value ends with terminal punctuation, so a
        // comma join would read "…at 9:57 PM., scheduled…". The joiner and
        // period are code-level rather than a localized sentence-form key on
        // purpose: this string is only ever spoken, punctuation surfaces as a
        // pause, and a second key would force all 13 locales to re-adjudicate
        // punctuation for translations that carried over verbatim (#1225).
        let timeDisplay = DepartureTimeDisplay(arrivalDeparture: firstArrivalDeparture, formatters: self)
        if timeDisplay.scheduledTimeText != nil {
            value += " " + timeDisplay.accessibilityTimeDescription + "."
        }

        if arrivalDepartures.count >= 2 {
            let textToAppend: String
            let secondArrivalDeparture = arrivalDepartures[1]
            let secondArrDepTime = abs(secondArrivalDeparture.arrivalDepartureMinutes)
            let secondArrDepIsArrival = secondArrivalDeparture.arrivalDepartureStatus == .arriving

            if arrivalDepartures.count >= 3 {
                let thirdArrivalDeparture = arrivalDepartures[2]
                let thirdArrDepTime = abs(thirdArrivalDeparture.arrivalDepartureMinutes)
                let thirdArrDepIsArrival = thirdArrivalDeparture.arrivalDepartureStatus == .arriving

                let formatString: String
                switch (secondArrDepIsArrival, thirdArrDepIsArrival) {
                case (true, true): formatString = OBALoc("voiceover.bookmarkarrivaldata.value.followingtwoarrivals_fmt", value: "Following two arrivals in %d minutes and %d minutes.", comment: "Voiceover text describing the two additional arrivals in the near-future, regardless of realtime data availability.")
                case (false, false): formatString = OBALoc("voiceover.bookmarkarrivaldata.value.followingtwodepartures_fmt", value: "Following two departures in %d minutes and %d minutes.", comment: "Voiceover text describing the two additional departures in the near-future, regardless of realtime data availability.")
                case (true, false): formatString = OBALoc("voiceover.bookmarkarrivaldata.value.followingarrivalthendeparture_fmt", value: "Following arrival in %d minutes and departure in %d minutes.", comment: "Voiceover text describing an arrival, then a departure in the near-future, regardless of realtime data availability.")
                case (false, true): formatString = OBALoc("voiceover.bookmarkarrivaldata.value.followingdeparturethenarrival_fmt", value: "Following departure in %d minutes and arrival in %d minutes.", comment: "Voiceover text describing a departure, then an arrival in the near-future, regardless of realtime data availability.")
                }

                textToAppend = String(format: formatString, secondArrDepTime, thirdArrDepTime)
            } else {
                let formatString = secondArrDepIsArrival
                    ? OBALoc("voiceover.bookmarkarrivaldata.value.followingonearrival_fmt", value: "Following arrival in %d minutes.", comment: "Voiceover text describing the one additional arrival in the near-future, regardless of realtime data availability.")
                    : OBALoc("voiceover.bookmarkarrivaldata.value.followingonedeparture_fmt", value: "Following departure in %d minutes.", comment: "Voiceover text describing the one additional departure in the near-future, regardless of realtime data availability.")
                textToAppend = String(format: formatString, secondArrDepTime)
            }

            value += " " + textToAppend
        }

        return value
    }
}
