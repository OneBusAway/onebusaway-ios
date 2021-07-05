//
//  OBAFormattersKey.swift
//  OBAKitCore
//
//  Created by Alan Chu on 5/25/21.
//

import SwiftUI

public struct OBAFormattersKey: EnvironmentKey {
    static public let defaultValue: Formatters = Formatters(locale: .current, calendar: .current, themeColors: .shared)
}

extension EnvironmentValues {
    public var obaFormatters: Formatters {
        get { self[OBAFormattersKey.self] }
        set { self[OBAFormattersKey.self] = newValue }
    }
}
