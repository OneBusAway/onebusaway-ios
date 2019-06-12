//
//  Strings.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 12/30/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import Foundation

public class Strings: NSObject {

    public static let bookmark = NSLocalizedString("common.bookmark", value: "Bookmark", comment: "The verb 'to bookmark'.")

    public static let cancel = NSLocalizedString("common.cancel", value: "Cancel", comment: "The verb 'to cancel', i.e. to stop an action.")

    public static let close = NSLocalizedString("common.close", value: "Close", comment: "The verb 'to close'.")

    public static let delete = NSLocalizedString("common.delete", value: "Delete", comment: "The verb 'to delete', as in to destroy something.")

    public static let filter = NSLocalizedString("common.filter", value: "Filter", comment: "The verb 'to filter'.")

    public static let map = NSLocalizedString("common.map", value: "Map", comment: "The noun for a map.")

    public static let refresh = NSLocalizedString("common.refresh", value: "Refresh", comment: "The verb 'refresh', as in 'reload'.")

    public static let updatedAtFormat = NSLocalizedString("common.updated_at_fmt", value: "Updated: %@", comment: "A format string used to tell the user when the UI they are looking at was last updated. e.g. Updated: 9:41 AM. The time is calculated at runtime.")
    public static let updating = NSLocalizedString("common.updating", value: "Updating…", comment: "Used to tell the user that the UI they are looking at is actively being updated with new data from the server.")
}
