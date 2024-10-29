//
//  RefreshButton.swift
//  OBAWidget
//
//  Created by Manu on 2024-10-18.
//

import SwiftUI
import AppIntents
import WidgetKit

//  MARK: - RefreshWidgetIntent
/// Since there's no built-in user interaction method for reloading widget timelines,
/// this intent serves as a workaround to provide that functionality via a button.
struct RefreshWidgetIntent: AppIntent {
    static var title: LocalizedStringResource = "Refresh Widget"
    
    func perform() async throws -> some IntentResult {
        // This forces the widget to refresh
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}


/// A button to manually trigger the widget refresh.
struct RefreshButton: View {
    var body: some View {
        
        Button(intent: RefreshWidgetIntent()) {
            HStack(spacing: 2){
                Image(systemName: "arrow.trianglehead.clockwise")
                    .imageScale(.small)
                    .foregroundStyle(.white)
                
                Text("Refresh")
                    .font(.system(size: 12))
                    .foregroundColor(.white)
            }
            .padding(.horizontal,6)
            .padding(.vertical, 4)
            .background(Color(.brand))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
        
    }
}

