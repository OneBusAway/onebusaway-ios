//
//  DateFormatters.swift
//  OBAKit
//
//  Created by Prince Yadav on 08/03/25.
//


import Foundation

// Centralized date formatters for better performance and consistency
struct DateFormatters {
    // Singleton instance for better performance
    static let shared = DateFormatters()
    
    // Time formatters
    let shortTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()
    
    let mediumTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        formatter.dateStyle = .none
        return formatter
    }()
    
    // Date formatters
    let shortDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .none
        formatter.dateStyle = .short
        return formatter
    }()
    
    let mediumDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .none
        formatter.dateStyle = .medium
        return formatter
    }()
    
    // Combined formatters
    let shortDateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .short
        return formatter
    }()
    
    // Relative date formatter
    let relativeDateFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()
    
    // Format time based on user preference
    func formatTime(_ date: Date, showSeconds: Bool = false) -> String {
        if showSeconds {
            return mediumTimeFormatter.string(from: date)
        } else {
            return shortTimeFormatter.string(from: date)
        }
    }
    
    // Format relative time (e.g., "5 min ago")
    func formatRelativeTime(from date: Date) -> String {
        return relativeDateFormatter.localizedString(for: date, relativeTo: Date())
    }
}

