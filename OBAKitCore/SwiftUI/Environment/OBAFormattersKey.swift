//
//  OBAFormattersKey.swift
//  OBAKitCore
//
//  Created by Alan Chu on 5/25/21.
//

import SwiftUI

private struct OBAFormattersKey: EnvironmentKey {
    // nonisolated(unsafe): initialized once (static let) and only ever read by
    // SwiftUI environment lookups on the main thread.
    nonisolated(unsafe) static let defaultValue: Formatters = Formatters(locale: .current, calendar: .current, themeColors: .shared)
}

extension EnvironmentValues {
    public var obaFormatters: Formatters {
        get { self[OBAFormattersKey.self] }
        set { self[OBAFormattersKey.self] = newValue }
    }
}
