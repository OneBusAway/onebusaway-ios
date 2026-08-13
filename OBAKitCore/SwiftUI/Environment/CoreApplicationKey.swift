//
//  CoreApplicationKey.swift
//  OBAKitCore
//
//  Created by Alan Chu on 10/19/21.
//

import SwiftUI

public struct CoreApplicationKey: EnvironmentKey {
    static public let defaultValue: CoreApplication = {
        // SwiftUI environment lookups happen on the main thread, so the first
        // access (which runs this initializer) is main-actor in practice.
        MainActor.assumeIsolated {
            let userDefaults = UserDefaults(suiteName: Bundle.main.appGroup!)!
            let bundledRegions = Bundle.main.path(forResource: "regions", ofType: "json")!
            let config = CoreAppConfig(appBundle: Bundle.main, userDefaults: userDefaults, bundledRegionsFilePath: bundledRegions)
            return CoreApplication(config: config)
        }
    }()
}

extension EnvironmentValues {
    public var coreApplication: CoreApplication {
        get { self[CoreApplicationKey.self] }
        set { self[CoreApplicationKey.self] = newValue }
    }
}
