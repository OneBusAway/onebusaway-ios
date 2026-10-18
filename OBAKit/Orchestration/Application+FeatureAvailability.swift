//
//  Application+FeatureAvailability.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import OBAKitCore

// MARK: - Feature Availability

extension Application {
    /// Models feature availability state in the app.
    ///
    /// Some applications might have support for features, like push notifications, that other white label versions of the app might lack.
    /// `FeatureStatus` and `FeatureAvailability` describe whether those features are unavailable, not running, or available for use.
    public enum FeatureStatus {

        /// This feature is not available in this app.
        case off

        /// This feature is available, but is not fully configured for use.
        ///
        /// This might be due to a race condition, for instance, and the caller should assume that the feature may be available in the future.
        case notRunning

        /// This feature is available for use.
        case running
    }

    /// Describes feature availability state in the app.
    ///
    /// Some applications might have support for features, like push notifications, that other white label versions of the app might lack.
    /// `FeatureStatus` and `FeatureAvailability` describe whether those features are unavailable, not running, or available for use.
    public struct FeatureAvailability {
        private let config: AppConfig
        private weak var application: Application?

        init(config: AppConfig, application: Application) {
            self.config = config
            self.application = application
        }

        /// Feature status of the Obaco service.
        public var obaco: FeatureStatus {
            switch (application?.regionsService.currentRegion?.sidecarBaseURL, application?.obacoService) {
            case (nil, nil): return .off
            case (_, nil): return .notRunning
            default: return .running
            }
        }

        /// Feature status of push notifications.
        public var push: FeatureStatus {
            switch (config.pushServiceProvider, application?.pushService) {
            case (nil, nil): return .off
            case (_, nil): return .notRunning
            default: return .running
            }
        }

        /// Feature status of Deep Linking.
        public var deepLinking: FeatureStatus {
            switch (application?.regionsService.currentRegion?.sidecarBaseURL, application?.appLinksRouter) {
            case (nil, nil): return .off
            case (_, nil): return .notRunning
            default: return .running
            }
        }

        /// Feature status of OTP trip planning.
        public var tripPlanning: FeatureStatus {
            guard
                let region = application?.regionsService.currentRegion,
                region.supportsOTP
            else {
                return .off
            }

            return .running
        }
    }
}
