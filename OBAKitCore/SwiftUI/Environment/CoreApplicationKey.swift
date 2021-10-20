//
//  CoreApplicationKey.swift
//  OBAKitCore
//
//  Created by Alan Chu on 10/19/21.
//

import SwiftUI

public struct CoreApplicationKey: EnvironmentKey {
    static public let defaultValue: CoreApplication = {
        let userDefaults = UserDefaults(suiteName: Bundle.main.appGroup!)!
        let bundledRegions = Bundle.main.path(forResource: "regions", ofType: "json")!
        let config = CoreAppConfig(appBundle: Bundle.main, userDefaults: userDefaults, bundledRegionsFilePath: bundledRegions)
        return CoreApplication(config: config)
    }()
}

extension EnvironmentValues {
    public var coreApplication: CoreApplication {
        get { self[CoreApplicationKey.self] }
        set { self[CoreApplicationKey.self] = newValue }
    }
}
