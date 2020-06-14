//
//  Formatters+TripBookmark.swift
//  OBAKit
//
//  Created by Alan Chu on 6/11/20.
//

import OBAKitCore

extension Formatters {
    /// Generates a localized label ideal for Voiceover describing the provided `BookmarkArrivalData`.
    /// As the method name suggests, this value is best used for the `UIAccessibility.accessibilityLabel` property.
    /// - parameter bookmarkArrivalData: The `BookmarkArrivalData` to describe.
    /// - returns: A localized Voiceover label describing the provided `BookmarkArrivalData`.
    func accessibilityLabel(for bookmarkArrivalData: BookmarkArrivalData) -> String {
        let bookmark = bookmarkArrivalData.bookmark
        let stringFormat: String
        if bookmark.isTripBookmark {
            stringFormat = bookmark.isFavorite
                ? OBALoc("voiceover.bookmarkarrivaldata.label.favoriteroutebookmark_fmt", value: "Favorite Route Bookmark, %@", comment: "Format string describing a favorite route (or trip) bookmark with a placeholder for the bookmark's name.")
                : OBALoc("voiceover.bookmarkarrivaldata.label.routebookmark_fmt", value: "Route Bookmark, %@", comment: "Format string describing a normal route (or trip) bookmark with a placeholder for the bookmark's name.")
        } else {
            stringFormat = OBALoc("voiceover.bookmarkarrivaldata.label.stopbookmark_fmt", value: "Stop Bookmark, %@", comment: "Format string describing a stop bookmark with a placeholder for the bookmark's name.")
        }

        return String(format: stringFormat, bookmark.name)
    }

    /// Generates a localized string value ideal for Voiceover describing the provided `BookmarkArrivalData`.
    /// As the method name suggests, this value is best used for the `UIAccessibility.accessibilityValue` property.
    /// - parameter bookmarkArrivalData: The `BookmarkArrivalData` to describe.
    /// - returns: A localized Voiceover value describing the provided `BookmarkArrivalData`.
    func accessibilityValue(for bookmarkArrivalData: BookmarkArrivalData) -> String? {
        guard bookmarkArrivalData.bookmark.isTripBookmark else { return nil }

        guard let arrivalDepartures = bookmarkArrivalData.arrivalDepartures,
            let firstArrivalDeparture = arrivalDepartures.first else {
                return OBALoc("voiceover.bookmarkarrivaldata.value.noupcomingdepartures_fmt", value: "No upcoming departures", comment: "Voiceover text describing no departures in the near-future.")
        }

        var value = self.accessibilityValue(for: firstArrivalDeparture)

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
                case (true, true):  formatString = OBALoc("voiceover.bookmarkarrivaldata.value.followingtwoarrivals_fmt", value: "Following two arrivals in %d minutes and %d minutes.", comment: "Voiceover text describing the two additional arrivals in the near-future, regardless of realtime data availability.")
                case (false, false):formatString = OBALoc("voiceover.bookmarkarrivaldata.value.followingtwodepartures_fmt", value: "Following two departures in %d minutes and %d minutes.", comment: "Voiceover text describing the two additional departures in the near-future, regardless of realtime data availability.")
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
