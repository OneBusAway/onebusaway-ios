import SwiftUI

// Define a color theme for the app that works in both light and dark modes
struct AppColors {
    // Primary brand colors
    static let primary = Color("PrimaryColor")
    static let secondary = Color("SecondaryColor")
    static let accent = Color("AccentColor")
    
    // Background colors
    static let background = Color("BackgroundColor")
    static let secondaryBackground = Color("SecondaryBackgroundColor")
    static let tertiaryBackground = Color("TertiaryBackgroundColor")
    static let cardBackground = Color("CardBackgroundColor")
    
    // Text colors
    static let primaryText = Color("PrimaryTextColor")
    static let secondaryText = Color("SecondaryTextColor")
    static let tertiaryText = Color("TertiaryTextColor")
    
    // Status colors
    static let success = Color("SuccessColor")
    static let warning = Color("WarningColor")
    static let error = Color("ErrorColor")
    
    // Utility colors
    static let divider = Color("DividerColor")
    
    // Helper function to get adaptive gray levels using pure SwiftUI
    static func adaptiveGray(_ level: Int) -> Color {
        switch level {
        case 1:
            return Color.gray
        case 2:
            return Color.gray.opacity(0.8)
        case 3:
            return Color.gray.opacity(0.7)
        case 4:
            return Color.gray.opacity(0.6)
        case 5:
            return Color.gray.opacity(0.5)
        case 6:
            return Color.gray.opacity(0.4)
        default:
            return Color.gray
        }
    }
    
    // Dynamic colors based on environment
    static func dynamicBackground(for colorScheme: ColorScheme) -> Color {
        return colorScheme == .dark ? background : .white
    }
        
    static func dynamicCardBackground(for colorScheme: ColorScheme) -> Color {
        return colorScheme == .dark ? cardBackground : .white
    }
}
