//
//  DataLoadFeedbackGeneratorTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import XCTest
import Nimble
import UIKit
@testable import OBAKit

class DataLoadFeedbackGeneratorTests: OBATestCase {
    
    var feedbackGenerator: DataLoadFeedbackGenerator!
    
    override func setUp() async throws {
        try await super.setUp()
        feedbackGenerator = DataLoadFeedbackGenerator(userDefaults: userDefaults)
    }
    
    func test_init_registersDefaults() {
        _ = DataLoadFeedbackGenerator(userDefaults: userDefaults)
        
        expect(self.userDefaults.bool(forKey: DataLoadFeedbackGenerator.EnabledUserDefaultsKey)) == true
    }
    
    func test_init_withApplication() {
        // Inject a MockDataLoader instead of the `AppConfig(appBundle:userDefaults:analytics:)`
        // convenience init, which defaults to `URLSession.shared`. `Application.init` calls
        // `regionsService.updateRegionsList()`, so that init would hit the live regions server.
        let dataLoader = MockDataLoader(testName: name)
        stubRegions(dataLoader: dataLoader)

        let locationService = LocationService(userDefaults: userDefaults, locationManager: LocationManagerMock())
        let config = AppConfig(
            regionsBaseURL: regionsURL,
            apiKey: apiKey,
            appVersion: appVersion,
            userDefaults: userDefaults,
            analytics: nil,
            queue: OperationQueue(),
            locationService: locationService,
            bundledRegionsFilePath: bundledRegionsPath,
            regionsAPIPath: regionsAPIPath,
            dataLoader: dataLoader
        )
        let application = Application(config: config)
        let generator = DataLoadFeedbackGenerator(application: application)

        expect(generator).toNot(beNil())
    }
    
    func test_dataLoad_success() {
        // Enable feedback
        userDefaults.set(true, forKey: DataLoadFeedbackGenerator.EnabledUserDefaultsKey)
        
        // This should not crash and should complete successfully
        feedbackGenerator.dataLoad(.success)
        
        expect(true).to(beTrue()) // Test that it doesn't crash
    }
    
    func test_dataLoad_failed() {
        // Enable feedback
        userDefaults.set(true, forKey: DataLoadFeedbackGenerator.EnabledUserDefaultsKey)
        
        // This should not crash and should complete successfully
        feedbackGenerator.dataLoad(.failed)
        
        expect(true).to(beTrue()) // Test that it doesn't crash
    }
    
    func test_dataLoad_disabled() {
        // Disable feedback
        userDefaults.set(false, forKey: DataLoadFeedbackGenerator.EnabledUserDefaultsKey)
        
        // This should not crash and should complete successfully
        feedbackGenerator.dataLoad(.success)
        feedbackGenerator.dataLoad(.failed)
        
        expect(true).to(beTrue()) // Test that it doesn't crash
    }
    
    func test_feedbackType_cases() {
        // Test that the enum cases exist
        let successType = DataLoadFeedbackGenerator.FeedbackType.success
        let failedType = DataLoadFeedbackGenerator.FeedbackType.failed
        
        expect(successType).to(equal(.success))
        expect(failedType).to(equal(.failed))
    }
}
