//
//  LocalizationKeys.swift
//  OBAWidget
//
//  Created by Manu on 2024-10-23.
//

// MARK: - LocalizationKeys Enum

internal enum LocalizationKeys {

    static let tapForMoreInformation      = OBALoc("today_screen.tap_for_more_information",
                                                   value: "Tap for more information",
                                                   comment: "Tap for more information subheading on Today view")

    static let noDeparturesInNextNMinutes = OBALoc("today_view.no_departures_in_next_n_minutes_fmt",
                                                   value: "No departures in the next %@ minutes",
                                                   comment: "")

    static let emptyStateString           = OBALoc("today_screen.no_data_description",
                                                   value: "Add bookmarks to Today View Bookmarks to see them here.",
                                                   comment: "")

}
