//
//  AgencyAlertsTestDeviceGatingTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import XCTest
import Nimble
@testable import OBAKit
@testable import OBAKitCore

/// Test alerts are a preview channel for OBACloud admins: displaying them requires
/// both the "Display test alerts" switch *and* a Test Device Name, mirroring how
/// push registration only sends `test_device=true` once the device is named.
class AgencyAlertsTestDeviceGatingTests: OBATestCase {

    private func setTestDeviceName(_ name: String?) {
        userDefaults.set(name, forKey: AgencyAlertsStore.UserDefaultKeys.testDeviceDescription)
    }

    private func setDisplayTestAlerts(_ enabled: Bool) {
        userDefaults.set(enabled, forKey: AgencyAlertsStore.UserDefaultKeys.displayRegionalTestAlerts)
    }

    func test_switchOff_noName_doesNotDisplay() {
        setDisplayTestAlerts(false)

        expect(AgencyAlertsStore.shouldDisplayTestAlerts(userDefaults: self.userDefaults)) == false
    }

    func test_switchOn_noName_doesNotDisplay() {
        setDisplayTestAlerts(true)

        expect(AgencyAlertsStore.shouldDisplayTestAlerts(userDefaults: self.userDefaults)) == false
    }

    func test_switchOn_whitespaceOnlyName_doesNotDisplay() {
        setDisplayTestAlerts(true)
        setTestDeviceName("   \n")

        expect(AgencyAlertsStore.shouldDisplayTestAlerts(userDefaults: self.userDefaults)) == false
    }

    func test_switchOff_withName_doesNotDisplay() {
        setDisplayTestAlerts(false)
        setTestDeviceName("Aaron's iPhone")

        expect(AgencyAlertsStore.shouldDisplayTestAlerts(userDefaults: self.userDefaults)) == false
    }

    func test_switchOn_withName_displays() {
        setDisplayTestAlerts(true)
        setTestDeviceName("Aaron's iPhone")

        expect(AgencyAlertsStore.shouldDisplayTestAlerts(userDefaults: self.userDefaults)) == true
    }

    func test_keyMatchesPushRegistrationManagersKey() {
        // The gate reads the same defaults entry that the Settings form writes and
        // PushRegistrationManager reads — if these diverge, the gate silently breaks.
        expect(AgencyAlertsStore.UserDefaultKeys.testDeviceDescription) == PushRegistrationManager.testDeviceDescriptionDefaultsKey
    }
}
