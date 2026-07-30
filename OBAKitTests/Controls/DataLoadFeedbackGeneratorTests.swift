//
//  DataLoadFeedbackGeneratorTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
import UIKit
@testable import OBAKit

@Suite(.serialized)
final class DataLoadFeedbackGeneratorTests: OBATestCase {
    
    var feedbackGenerator: DataLoadFeedbackGenerator!
    
    override init() async throws {
        try await super.init()

        feedbackGenerator = DataLoadFeedbackGenerator(userDefaults: userDefaults)
    }
    
    @Test func `Init registers defaults`() {
        _ = DataLoadFeedbackGenerator(userDefaults: userDefaults)
        
        #expect(self.userDefaults.bool(forKey: DataLoadFeedbackGenerator.EnabledUserDefaultsKey) == true)
    }
    
    @Test func `Init with application`() {
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
        _ = DataLoadFeedbackGenerator(application: application)
    }
    
    @Test func `Data load success`() {
        // Enable feedback
        userDefaults.set(true, forKey: DataLoadFeedbackGenerator.EnabledUserDefaultsKey)
        
        // This should not crash and should complete successfully
        feedbackGenerator.dataLoad(.success)
        
        #expect(true)  // Test that it doesn't crash
    }
    
    @Test func `Data load failed`() {
        // Enable feedback
        userDefaults.set(true, forKey: DataLoadFeedbackGenerator.EnabledUserDefaultsKey)
        
        // This should not crash and should complete successfully
        feedbackGenerator.dataLoad(.failed)
        
        #expect(true)  // Test that it doesn't crash
    }
    
    @Test func `Data load disabled`() {
        // Disable feedback
        userDefaults.set(false, forKey: DataLoadFeedbackGenerator.EnabledUserDefaultsKey)
        
        // This should not crash and should complete successfully
        feedbackGenerator.dataLoad(.success)
        feedbackGenerator.dataLoad(.failed)
        
        #expect(true)  // Test that it doesn't crash
    }
    
    @Test func `Feedback type cases`() {
        // Test that the enum cases exist
        let successType = DataLoadFeedbackGenerator.FeedbackType.success
        let failedType = DataLoadFeedbackGenerator.FeedbackType.failed
        
        #expect(successType == .success)
        #expect(failedType == .failed)
    }
}
