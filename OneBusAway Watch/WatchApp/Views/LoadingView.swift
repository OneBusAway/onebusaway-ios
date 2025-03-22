//
//  LoadingView.swift
//  OBAKit
//
//  Created by Prince Yadav on 06/03/25.
//


import SwiftUI

struct LoadingView: View {
    // Dynamic sizing for different watch sizes
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @Environment(\.displayScale) var displayScale
    @Environment(\.colorScheme) var colorScheme
    
    // Computed properties for responsive design
    private var fontSize: CGFloat {
        return horizontalSizeClass == .regular ? (displayScale > 2 ? 18 : 16) : 14
    }
    
    private var indicatorScale: CGFloat {
        return horizontalSizeClass == .regular ? (displayScale > 2 ? 1.8 : 1.5) : 1.2
    }
    
    private var spacing: CGFloat {
        return horizontalSizeClass == .regular ? (displayScale > 2 ? 20 : 16) : 12
    }
    
    private var padding: CGFloat {
        return horizontalSizeClass == .regular ? (displayScale > 2 ? 30 : 24) : 20
    }
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .edgesIgnoringSafeArea(.all)
            
            VStack(spacing: spacing) {
                ProgressView()
                    .scaleEffect(indicatorScale)
                
                Text("Loading...")
                    .font(.system(size: fontSize, weight: .medium))
                    .foregroundColor(.white)
            }
            .padding(padding)
            .background(AppColors.adaptiveGray(3).opacity(0.7))
            .cornerRadius(16)
            .shadow(radius: 5)
        }
    }
}

struct LoadingView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            // Preview for smaller watches (38mm, 40mm)
            LoadingView()
                .previewDevice("Apple Watch Series 4 (40mm)")
                .previewDisplayName("Series 4 (40mm)")
            
            // Preview for larger watches (44mm, 45mm)
            LoadingView()
                .previewDevice("Apple Watch Series 7 (45mm)")
                .previewDisplayName("Series 7 (45mm)")
            
            // Preview for Apple Watch Ultra
            LoadingView()
                .previewDevice("Apple Watch Ultra")
                .previewDisplayName("Apple Watch Ultra")
        }
    }
}

