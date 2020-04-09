//
//  Strings.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 12/30/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import Foundation

public class Strings: NSObject {

    public static let alarm = OBALoc("common.alarm", value: "Alarm", comment: "The noun, like an alarm clock or an alarm bell.")

    public static let back = OBALoc("common.back", value: "Back", comment: "Back, as in 'back to the previous screen.'")

    public static let bookmark = OBALoc("common.bookmark", value: "Bookmark", comment: "The verb 'to bookmark'.")

    public static let cancel = OBALoc("common.cancel", value: "Cancel", comment: "The verb 'to cancel', i.e. to stop an action.")

    public static let close = OBALoc("common.close", value: "Close", comment: "The verb 'to close'.")

    public static let `continue` = OBALoc("common.continue", value: "Continue", comment: "The verb 'to continue'.")

    public static let delete = OBALoc("common.delete", value: "Delete", comment: "The verb 'to delete', as in to destroy something.")

    public static let dismiss = OBALoc("common.dismiss", value: "Dismiss", comment: "The verb 'to dismiss', as in to hide or get rid of something. Used as a button title on alerts.")

    public static let done = OBALoc("common.done", value: "Done", comment: "Past participle of 'do'. As in 'I am done' or 'I am finished.'")

    public static let edit = OBALoc("common.edit", value: "Edit", comment: "The verb 'to edit', as in to change or modify something. Used as a button title.")

    public static let error = OBALoc("common.error", value: "Error", comment: "The noun 'error', as in 'something went wrong'.")

    public static let filter = OBALoc("common.filter", value: "Filter", comment: "The verb 'to filter'.")

    public static let learnMore = OBALoc("common.learn_more", value: "Learn More", comment: "This is button text that tells the user they can tap on it to learn more about the topic at hand.")

    public static let loading = OBALoc("common.loading", value: "Loading…", comment: "Used to indicate that content is loading.")

    public static let map = OBALoc("common.map", value: "Map", comment: "The noun for a map.")

    public static let more = OBALoc("common.more", value: "More", comment: "As in 'see more' or 'learn more'.")

    public static let ok = OBALoc("common.ok", value: "OK", comment: "OK")

    public static let recentStops = OBALoc("common.recent_stops", value: "Recent Stops", comment: "i.e. recently viewed or visited stops for transit vehicles, like a bus stop, ferry terminal, or train station.")

    public static let refresh = OBALoc("common.refresh", value: "Refresh", comment: "The verb 'refresh', as in 'reload'.")

    public static let save = OBALoc("common.save", value: "Save", comment: "The verb 'save', as in 'save data'.")

    public static let scheduledNotRealTime = OBALoc("common.scheduled_not_real_time", value: "Scheduled/not real-time", comment: "Explains that this is departure comes from schedule data, not from a real-time vehicle location.")

    public static let settings = OBALoc("common.settings", value: "Settings", comment: "A noun referring to a collection of options for adjusting app behavior.")

    public static let skip = OBALoc("common.skip", value: "Skip", comment: "The verb 'to skip' as in 'don't perform a particular step and go on to the next one instead.'")

    public static let updatedAtFormat = OBALoc("common.updated_at_fmt", value: "Updated: %@", comment: "A format string used to tell the user when the UI they are looking at was last updated. e.g. Updated: 9:41 AM. The time is calculated at runtime.")

    public static let updating = OBALoc("common.updating", value: "Updating…", comment: "Used to tell the user that the UI they are looking at is actively being updated with new data from the server.")

    public static let emptyBookmarkTitle = OBALoc("common.empty_bookmark_set.title", value: "No Bookmarks", comment: "Title for the bookmark empty set indicator.")

    public static let emptyBookmarkBody = OBALoc("common.empty_bookmark_set.body", value: "Add a bookmark for a stop or trip to easily access it here.", comment: "Body for the bookmark empty set indicator.")
}
