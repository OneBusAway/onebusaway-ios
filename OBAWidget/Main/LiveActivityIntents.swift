//
//  LiveActivityIntents.swift
//  OBAWidget
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import AppIntents
import Foundation
import OBAKitCore

/// Shared control handler configured for the `OBAWidget` extension bundle.
private enum LiveActivityWidgetController {
    static func makeHandler() -> LiveActivityControlHandler {
        LiveActivityControlHandler(
            appGroupIdentifier: Bundle.main.appGroup,
            bundledRegionsFilePath: Bundle.main.bundledRegionsFilePath,
            restServerAPIKey: Bundle.main.restServerAPIKey,
            appVersion: Bundle.main.appVersion
        )
    }
}

/// Refreshes a running Live Activity's departures directly from the widget extension
/// without launching the main app.
struct RefreshLiveActivityIntent: LiveActivityIntent {
    static let title = LocalizedStringResource(
        "refresh_live_activity_intent.title",
        defaultValue: "Refresh Live Activity",
        table: "AppIntents",
        bundle: #bundle
    )
    static let isDiscoverable = false
    static let openAppWhenRun = false

    @Parameter(title: LocalizedStringResource(
        "live_activity_intent.activity_id_parameter_title",
        defaultValue: "Activity ID",
        table: "AppIntents",
        bundle: #bundle
    ))
    var activityID: String

    init() {}

    init(activityID: String) {
        self.activityID = activityID
    }

    func perform() async throws -> some IntentResult {
        await LiveActivityWidgetController.makeHandler().refresh(activityID: activityID)
        return .result()
    }
}

/// Immediately ends and dismisses a running Live Activity from the Lock Screen card
/// without launching the main app.
struct EndLiveActivityIntent: LiveActivityIntent {
    static let title = LocalizedStringResource(
        "end_live_activity_intent.title",
        defaultValue: "End Live Activity",
        table: "AppIntents",
        bundle: #bundle
    )
    static let isDiscoverable = false
    static let openAppWhenRun = false

    @Parameter(title: LocalizedStringResource(
        "live_activity_intent.activity_id_parameter_title",
        defaultValue: "Activity ID",
        table: "AppIntents",
        bundle: #bundle
    ))
    var activityID: String

    init() {}

    init(activityID: String) {
        self.activityID = activityID
    }

    func perform() async throws -> some IntentResult {
        await LiveActivityWidgetController.makeHandler().end(activityID: activityID)
        return .result()
    }
}
