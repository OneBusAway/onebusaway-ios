//
//  OpenStopIntent.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import AppIntents
import OBAKitCore

/// Opens a stop from Shortcuts, and from Spotlight once stops are indexed (#1555).
///
/// Declares neither `openAppWhenRun` nor `supportedModes`: `OpenIntent`
/// supplies the first, and moving the app's intents to `supportedModes` is #1557.
///
/// Not `nonisolated`, for the same `@Parameter` reason as `TrackBookmarkIntent`.
/// Strings come from `AppIntents.strings`; see `TrackBookmarkIntent` for why.
public struct OpenStopIntent: OpenIntent {
    public static let title = LocalizedStringResource("open_stop_intent.title", defaultValue: "Open Stop", table: "AppIntents")
    public static let description = IntentDescription(LocalizedStringResource("open_stop_intent.description", defaultValue: "Open a stop to see its departures.", table: "AppIntents"))

    public init() {}

    @Parameter(title: LocalizedStringResource("stop_entity.parameter_title", defaultValue: "Stop", table: "AppIntents"))
    public var target: StopEntity

    public func perform() async throws -> some IntentResult {
        OpenStopRequest.post(target.destination)
        return .result()
    }
}

extension Notification.Name {
    /// Posted by `OpenStopRequest.post(_:)`. `Application` opens the stop.
    nonisolated static let openStopRequested = Notification.Name("OBA.OpenStopRequested")
}

/// Hands an Open Stop request to `Application`, which an intent can't reach.
///
/// Track Bookmark also keeps a durable copy of its request in `UserDefaults`;
/// this doesn't need one. `AppDelegate.init` builds `Application`, which
/// observes this notification from its own `init`, so the observer exists
/// before any intent runs in the app process. From there
/// `Application.queueOrOpenStop(_:)` holds the stop until the UI and region
/// are ready.
nonisolated enum OpenStopRequest {
    static let destinationUserInfoKey = "destination"

    static func post(_ destination: AppLinksRouter.StopDestination) {
        NotificationCenter.default.post(name: .openStopRequested, object: nil, userInfo: [destinationUserInfoKey: destination])
    }
}
