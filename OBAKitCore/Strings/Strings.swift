//
//  Strings.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

public class Strings: NSObject {

    public static let addAlarm = OBALoc("common.add_alarm", value: "Add Alarm", comment: "This will appear on a button or as a title, and indicates that this UI will create a new bookmark.")

    public static let addBookmark = OBALoc("common.add_bookmark", value: "Add Bookmark", comment: "This will appear on a button or as a title, and indicates that this UI will create a new bookmark.")

    public static let alarm = OBALoc("common.alarm", value: "Alarm", comment: "The noun, like an alarm clock or an alarm bell.")

    public static let back = OBALoc("common.back", value: "Back", comment: "Back, as in 'back to the previous screen.'")

    public static let bookmark = OBALoc("common.bookmark", value: "Bookmark", comment: "The verb 'to bookmark'.")

    public static let cancel = OBALoc("common.cancel", value: "Cancel", comment: "The verb 'to cancel', i.e. to stop an action.")

    public static let close = OBALoc("common.close", value: "Close", comment: "The verb 'to close'.")

    public static let `continue` = OBALoc("common.continue", value: "Continue", comment: "The verb 'to continue'.")

    public static let delete = OBALoc("common.delete", value: "Delete", comment: "The verb 'to delete', as in to destroy something.")

    public static let donate = OBALoc("common.donate", value: "Donate", comment: "The verb 'to donate', as in to give money to a charitable cause.")

    public static let confirmDelete = OBALoc("common.confirmdelete", value: "Confirm Delete", comment: "Asks the user to confirm a delete action. Typically this is showned when the user taps a 'delete' button on an important item.")

    public static let dismiss = OBALoc("common.dismiss", value: "Dismiss", comment: "The verb 'to dismiss', as in to hide or get rid of something. Used as a button title on alerts.")

    public static let done = OBALoc("common.done", value: "Done", comment: "Past participle of 'do'. As in 'I am done' or 'I am finished.'")

    public static let edit = OBALoc("common.edit", value: "Edit", comment: "The verb 'to edit', as in to change or modify something. Used as a button title.")

    public static let error = OBALoc("common.error", value: "Error", comment: "The noun 'error', as in 'something went wrong'.")

    public static let exportData = OBALoc("common.export_data", value: "Export Data", comment: "The title of a button that exports all of the user's data into a file.")

    public static let filter = OBALoc("common.filter", value: "Filter", comment: "The verb 'to filter'.")

    public static let learnMore = OBALoc("common.learn_more", value: "Learn More", comment: "This is button text that tells the user they can tap on it to learn more about the topic at hand.")

    public static let loading = OBALoc("common.loading", value: "Loading…", comment: "Used to indicate that content is loading.")

    public static let locationUnavailable = OBALoc("common.location_unavailable", value: "Location Unavailable", comment: "A common error message that can be used when the user's location is not available and we need it to accomplish something.")

    public static let map = OBALoc("common.map", value: "Map", comment: "The noun for a map.")

    public static let migrateData = OBALoc("common.migrate_data", value: "Migrate Data", comment: "A title or command for upgrading data from older versions of OBA.")

    public static let migrateDataDescription = OBALoc("common.migrate_data_description", value: "Upgrade your recent stops and bookmarks to work with the latest version of the app. (Requires an internet connection.)", comment: "An explanation about what the Migrate Data feature does.")

    public static let more = OBALoc("common.more", value: "More", comment: "As in 'see more' or 'learn more'.")

    public static let ok = OBALoc("common.ok", value: "OK", comment: "OK")

    public static let recentStops = OBALoc("common.recent_stops", value: "Recent Stops", comment: "i.e. recently viewed or visited stops for transit vehicles, like a bus stop, ferry terminal, or train station.")

    public static let refresh = OBALoc("common.refresh", value: "Refresh", comment: "The verb 'refresh', as in 'reload'.")

    public static let save = OBALoc("common.save", value: "Save", comment: "The verb 'save', as in 'save data'.")

    public static let scheduledNotRealTime = OBALoc("common.scheduled_not_real_time", value: "Scheduled/not real-time", comment: "Explains that this is departure comes from schedule data, not from a real-time vehicle location.")

    public static let serviceAlert = OBALoc("common.service_alert", value: "Service Alert", comment: "A noun referring to an alert about service interruptions, reroutes, or other disruptions or changes.")

    public static let serviceAlerts = OBALoc("common.service_alerts", value: "Service Alerts", comment: "Plural form of a noun referring to an alert about service interruptions, reroutes, or other disruptions or changes.")

    public static let settings = OBALoc("common.settings", value: "Settings", comment: "A noun referring to a collection of options for adjusting app behavior.")

    public static let share = OBALoc("common.share", value: "Share", comment: "A verb referring to sharing something generic.")

    public static let shareTrip = OBALoc("common.share_trip", value: "Share Trip", comment: "Button title for sharing the status of your trip (i.e. location, arrival time, etc.)")

    public static let skip = OBALoc("common.skip", value: "Skip", comment: "The verb 'to skip' as in 'don't perform a particular step and go on to the next one instead.'")

    public static let sort = OBALoc("common.sort", value: "Sort", comment: "The verb 'to sort' as in to arrange things in an order.")

    public static let stops = OBALoc("common.stops", value: "Stops", comment: "Noun. Plural form of a transit stop.")

    public static let updatedAtFormat = OBALoc("common.updated_at_fmt", value: "Updated: %@", comment: "A format string used to tell the user when the UI they are looking at was last updated. e.g. Updated: 9:41 AM. The time is calculated at runtime.")

    public static let updating = OBALoc("common.updating", value: "Updating…", comment: "Used to tell the user that the UI they are looking at is actively being updated with new data from the server.")

    public static let emptyBookmarkTitle = OBALoc("common.empty_bookmark_set.title", value: "No Bookmarks", comment: "Title for the bookmark empty set indicator.")

    public static let emptyBookmarkBody = OBALoc("common.empty_bookmark_set.body", value: "Add a bookmark for a stop or trip to easily access it here.", comment: "Body for the bookmark empty set indicator.")

    public static let emptyBookmarkBodyWithPendingMigration = OBALoc("common.empty_bookmark_set.body_with_pending_migration", value: "Go to the More tab > Settings > Migrate Data to see your bookmarks appear here.", comment: "Body for the bookmark empty set indicator when the user has a pending migration from the old version of the app.")

    public static let emptyAlertTitle = OBALoc("common.empty_alert_set.title", value: "No Alerts", comment: "Title for the alert empty set indicator.")
}
