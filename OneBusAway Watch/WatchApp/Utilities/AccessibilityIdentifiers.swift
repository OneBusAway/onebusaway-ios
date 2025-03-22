//
//  AccessibilityIdentifiers.swift
//  OBAKit
//
//  Created by Prince Yadav on 08/03/25.
//

import SwiftUI

// Extension to improve accessibility throughout the app
extension View {
    func accessibilityLabel(_ label: String) -> some View {
        self.accessibility(label: Text(label))
    }
    
    func accessibilityHint(_ hint: String) -> some View {
        self.accessibility(hint: Text(hint))
    }
    
    // Change to use the existing native View return type from the base methods
    func accessibilityAction(named name: String, action: @escaping () -> Void) -> Self {
        self.accessibilityAction(named: name, action: action)
    }
    
    func dynamicTypeSize(_ range: ClosedRange<DynamicTypeSize> = .xSmall...DynamicTypeSize.accessibility3) -> Self {
        self.dynamicTypeSize(range)
    }
}

// Accessibility identifiers for UI testing
struct AccessibilityIdentifiers {
    static let nearbyStopsTab = "nearbyStopsTab"
    static let favoritesTab = "favoritesTab"
    static let settingsTab = "settingsTab"
    static let stopsList = "stopsList"
    static let searchField = "searchField"
    static let refreshButton = "refreshButton"
    static let favoriteButton = "favoriteButton"
    static let arrivalsList = "arrivalsList"
    static let syncButton = "syncButton"
}
