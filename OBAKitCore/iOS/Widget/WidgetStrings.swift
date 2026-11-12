//
//  WidgetStrings.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

#if os(iOS)

import Foundation

/// Copy for the home-screen bookmarks widget (OBAWidget).
///
/// Lives in OBAKitCore for the same reason as `LiveActivityStaleChrome`: the
/// widget extension links OBAKitCore, so these resolve from OBAKitCore's
/// translated `Localizable.strings` and `scripts/extract_strings` picks them up
/// with the rest of the module. The extension's own `.lproj`s hold only its
/// `AppIntents.strings`, which the system reads out of process.
///
/// Computed rather than stored so a language change takes effect on the next
/// timeline render instead of being frozen at first access.
public enum WidgetStrings {
    /// Name of the widget in the Add Widget gallery.
    public static var galleryDisplayName: String {
        OBALoc("widget.gallery.display_name", value: "Bookmarks", comment: "Name of the bookmarks widget in the iOS Add Widget gallery.")
    }

    /// Description of the widget in the Add Widget gallery.
    public static var galleryDescription: String {
        OBALoc("widget.gallery.description", value: "See upcoming departures for your bookmarks.", comment: "Description of the bookmarks widget in the iOS Add Widget gallery.")
    }

    /// Row subtitle when departures for a bookmark have not been loaded.
    public static var tapForMoreInformation: String {
        OBALoc("widget.tap_for_more_information", value: "Tap for more information", comment: "Widget row subtitle when departures for a bookmark are not loaded yet. Tapping opens the stop in the app.")
    }

    /// Row subtitle when a bookmark has nothing coming within `minutes`.
    public static func noDepartures(inNextMinutes minutes: Int) -> String {
        let fmt = OBALoc("widget.no_departures_in_next_minutes_fmt", value: "No departures in the next %d min", comment: "Widget row subtitle when a bookmark has no departures soon. %d is a number of minutes (currently always 60); the abbreviation avoids plural agreement.")
        return String(format: fmt, locale: .current, minutes)
    }

    /// Shown in place of rows when no bookmark is set to appear in the widget.
    public static var emptyState: String {
        OBALoc("widget.empty_state", value: "Turn on “Show in Today View widget” for a bookmark to see it here.", comment: "Widget empty state. Quotes the bookmark editor's switch title (edit_bookmark_controller.show_in_today_view_switch_title); keep the two identical.")
    }

    /// Header label: when the widget's data was fetched.
    /// - Parameter time: An already-formatted clock time, e.g. "9:41 AM".
    public static func lastUpdated(at time: String) -> String {
        let fmt = OBALoc("widget.last_updated_fmt", value: "Last updated at %@", comment: "Widget header showing when departures were last fetched. %@ is a clock time such as 9:41 AM.")
        return String(format: fmt, time)
    }

    /// Name of the next-departure complication widget in the Add Widget gallery.
    public static var nextDepartureGalleryDisplayName: String {
        OBALoc("widget.next_departure.gallery.display_name", value: "Next Departure", comment: "Name of the next-departure Lock Screen and watch complication widget in the Add Widget gallery.")
    }

    /// Description of the next-departure complication widget in the Add Widget gallery.
    public static var nextDepartureGalleryDescription: String {
        OBALoc("widget.next_departure.gallery.description", value: "See the next upcoming departure for your top bookmark.", comment: "Description of the next-departure Lock Screen and watch complication widget in the Add Widget gallery.")
    }

    /// Short fallback label when a complication's bookmark has no upcoming departures.
    public static var complicationNoDepartures: String {
        OBALoc("widget.complication.no_departures", value: "No departures", comment: "Short fallback text on a Lock Screen or watch complication when a bookmark has no upcoming departures.")
    }

    /// Short fallback label when no bookmarks are configured for the complication.
    public static var complicationNoBookmarks: String {
        OBALoc("widget.complication.no_bookmarks", value: "No bookmarks", comment: "Short fallback text on a Lock Screen or watch complication when no bookmarks are configured.")
    }

    /// Short hint shown in a rectangular complication when no bookmarks are configured.
    public static var complicationNoBookmarksHint: String {
        OBALoc("widget.complication.no_bookmarks_hint", value: "Enable a widget bookmark in the app.", comment: "Hint shown in a rectangular Lock Screen or watch complication when no bookmarks are shown in the widget.")
    }

    /// Short fallback label when complication departure data is unavailable.
    public static var complicationUnavailable: String {
        OBALoc("widget.complication.unavailable", value: "Unavailable", comment: "Short fallback text on a Lock Screen or watch complication when departure data could not be loaded.")
    }
}

#endif // os(iOS)
