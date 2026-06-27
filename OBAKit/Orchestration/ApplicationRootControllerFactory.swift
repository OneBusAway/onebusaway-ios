//
//  ApplicationRootControllerFactory.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import UIKit
import OBAKitCore

/// `@objc` seam that the (Objective-C) AppDelegates call to build the
/// window's root view controller. Reads the map-panel feature flag and
/// returns either `ClassicApplicationRootController` (the UIKit tab bar) or
/// `MapPanelRootController` (the SwiftUI map-panel experience).
///
/// Centralising the branch here keeps each concrete root controller
/// single-purpose and removes the need for Obj-C callers to know about the
/// feature flag.
@objc(OBAApplicationRootControllerFactory)
public final class ApplicationRootControllerFactory: NSObject {

    @objc public static func make(application: Application) -> UIViewController {
        if application.userDefaults.bool(forKey: FeatureFlags.useMapPanelExperienceKey) {
            return MapPanelRootController(application: application)
        } else {
            return ClassicApplicationRootController(application: application)
        }
    }
}
