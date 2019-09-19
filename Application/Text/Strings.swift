//
//  Strings.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 12/30/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import Foundation

public class Strings: NSObject {

    public static let back = NSLocalizedString("common.back", value: "Back", comment: "Back, as in 'back to the previous screen.'")

    public static let bookmark = NSLocalizedString("common.bookmark", value: "Bookmark", comment: "The verb 'to bookmark'.")

    public static let cancel = NSLocalizedString("common.cancel", value: "Cancel", comment: "The verb 'to cancel', i.e. to stop an action.")

    public static let close = NSLocalizedString("common.close", value: "Close", comment: "The verb 'to close'.")

    public static let `continue` = NSLocalizedString("common.continue", value: "Continue", comment: "The verb 'to continue'.")

    public static let delete = NSLocalizedString("common.delete", value: "Delete", comment: "The verb 'to delete', as in to destroy something.")

    public static let dismiss = NSLocalizedString("common.dismiss", value: "Dismiss", comment: "The verb 'to dismiss', as in to hide or get rid of something. Used as a button title on alerts.")

    public static let error = NSLocalizedString("common.error", value: "Error", comment: "The noun 'error', as in 'something went wrong'.")

    public static let filter = NSLocalizedString("common.filter", value: "Filter", comment: "The verb 'to filter'.")

    public static let loading = NSLocalizedString("common.loading", value: "Loading…", comment: "Used to indicate that content is loading.")

    public static let map = NSLocalizedString("common.map", value: "Map", comment: "The noun for a map.")

    public static let refresh = NSLocalizedString("common.refresh", value: "Refresh", comment: "The verb 'refresh', as in 'reload'.")

    public static let save = NSLocalizedString("common.save", value: "Save", comment: "The verb 'save', as in 'save data'.")

    public static let scheduledNotRealTime = NSLocalizedString("common.scheduled_not_real_time", value: "Scheduled/not real-time", comment: "Explains that this is departure comes from schedule data, not from a real-time vehicle location.")

    public static let settings = NSLocalizedString("common.settings", value: "Settings", comment: "A noun referring to a collection of options for adjusting app behavior.")

    public static let updatedAtFormat = NSLocalizedString("common.updated_at_fmt", value: "Updated: %@", comment: "A format string used to tell the user when the UI they are looking at was last updated. e.g. Updated: 9:41 AM. The time is calculated at runtime.")

    public static let updating = NSLocalizedString("common.updating", value: "Updating…", comment: "Used to tell the user that the UI they are looking at is actively being updated with new data from the server.")
}
