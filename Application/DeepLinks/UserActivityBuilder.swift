//
//  UserActivityBuilder.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 5/31/19.
//

import Foundation
import Intents

/// Simplifies creating `NSUserActivity` objects suitable for use with Handoff and Siri.
@objc(OBAUserActivityBuilder)
public class UserActivityBuilder: NSObject {
    private let application: Application

    @objc public init(application: Application) {
        self.application = application
        super.init()

        validateInfoPlistUserActivityTypes()
    }

    public let stopIDUserInfoKey = "stopID"
    public let regionIDUserInfoKey = "regionID"

    @objc public func userActivity(for stop: Stop, region: Region) -> NSUserActivity {
        let activity = NSUserActivity(activityType: stopActivityType)
        activity.title = Formatters.formattedTitle(stop: stop)

        activity.isEligibleForHandoff = true

        // Per WWDC 2018 Session "Intro to Siri Shortcuts", this must be set to `true`
        // for `isEligibleForPrediction` to have any effect. Timecode: 8:30
        activity.isEligibleForSearch = true

        if #available(iOS 12.0, *) {
            activity.isEligibleForPrediction = true
            activity.suggestedInvocationPhrase = NSLocalizedString("user_activity_builder.show_me_my_bus", value: "Show me my bus", comment: "Suggested invocation phrase for Siri Shortcut")
            activity.persistentIdentifier = "region_\(region.regionIdentifier)_stop_\(stop.id)"
        }

        activity.requiredUserInfoKeys = [stopIDUserInfoKey, regionIDUserInfoKey]
        activity.userInfo = [stopIDUserInfoKey: stop.id, regionIDUserInfoKey: region.regionIdentifier]
        activity.webpageURL = application.deepLinkRouter.url(for: stop, region: region)

        return activity
    }

    // MARK: - Private Helpers

    private var stopActivityType: String {
        return "\(application.applicationBundle.bundleIdentifier).stop"
    }

    private var tripActivityType: String {
        return "\(application.applicationBundle.bundleIdentifier).trip"
    }

    /// Checks to see if the application's Info.plist file contains `NSUserActivityTypes` data
    /// that matches what this class expects it to have.
    private func validateInfoPlistUserActivityTypes() {
        guard
            let activityTypes = application.applicationBundle.userActivityTypes,
            activityTypes.contains(stopActivityType),
            activityTypes.contains(tripActivityType)
        else {
            fatalError("The Info.plist file must include the necessary NSUserActivityTypes values.")
        }
    }
}

//@objc public class func createUserActivity(name: String, stopID: String, regionID: Int) -> NSUserActivity {
//    let activity = NSUserActivity(activityType: OBAHandoff.activityTypeStop)
//    activity.title = name
//    activity.isEligibleForHandoff = true
//
//    // Per WWDC 2018 Session "Intro to Siri Shortcuts", this must be set to `true`
//    // for `isEligibleForPrediction` to have any effect. Timecode: 8:30
//    activity.isEligibleForSearch = true
//
//    if #available(iOS 12.0, *) {
//        activity.isEligibleForPrediction = true
//        activity.suggestedInvocationPhrase = NSLocalizedString("handoff.show_me_my_bus", comment: "Suggested invocation phrase for Siri Shortcut")
//        activity.persistentIdentifier = "region_\(regionID)_stop_\(stopID)"
//    }
//
//    activity.requiredUserInfoKeys = [OBAHandoff.stopIDKey, OBAHandoff.regionIDKey]
//    activity.userInfo = [OBAHandoff.stopIDKey: stopID, OBAHandoff.regionIDKey: regionID]
//
//    let deepLinkRouter = DeepLinkRouter(baseURL: URL(string: OBADeepLinkServerAddress)!)
//    activity.webpageURL = deepLinkRouter.deepLinkURL(stopID: stopID, regionID: regionID)
//
//    return activity
//}
