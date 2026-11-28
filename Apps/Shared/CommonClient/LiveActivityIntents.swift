//
//  LiveActivityIntents.swift
//  OneBusAway
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import AppIntents
import Foundation
import OBAKitCore

/// Shared control handler configured from the executing bundle (`App.app` when
/// the system invokes a `LiveActivityIntent` in the app process, or `OBAWidget.appex`).
private enum LiveActivityIntentController {
    static func makeHandler() -> LiveActivityControlHandler {
        LiveActivityControlHandler(
            appGroupIdentifier: Bundle.main.appGroup,
            bundledRegionsFilePath: Bundle.main.bundledRegionsFilePath,
            restServerAPIKey: Bundle.main.restServerAPIKey,
            appVersion: Bundle.main.appVersion
        )
    }
}

/// Refreshes a running Live Activity's departures without opening the app UI.
///
/// Conforms to `LiveActivityIntent` and is compiled into both the `App` target
/// (where `LiveActivityIntent.perform()` runs in a backgrounded app process) and
/// `OBAWidget` (whose `Button(intent:)` references the type).
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
        await LiveActivityIntentController.makeHandler().refresh(activityID: activityID)
        return .result()
    }
}

/// Immediately ends and dismisses a running Live Activity without opening the app UI.
///
/// Conforms to `LiveActivityIntent` and is compiled into both the `App` target
/// (where `LiveActivityIntent.perform()` runs in a backgrounded app process) and
/// `OBAWidget` (whose `Button(intent:)` references the type).
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
        await LiveActivityIntentController.makeHandler().end(activityID: activityID)
        return .result()
    }
}
