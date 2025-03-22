//
//  FavoritesView.swift
//  OBAKit
//
//  Created by Prince Yadav on 06/03/25.
//

import SwiftUI
import UIKit

struct FavoritesView: View {
    @EnvironmentObject private var favoritesViewModel: FavoritesViewModel
    @EnvironmentObject private var connectivityService: WatchConnectivityService
    @State private var isEditing = false
    @Environment(\.colorScheme) var colorScheme
    @AppStorage("darkMode") private var darkMode = false
    
    // Dynamic sizing for different watch sizes
    @Environment(\.sizeCategory) var sizeCategory
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @Environment(\.displayScale) var displayScale
    
    // Computed properties for responsive design
    private var fontSize: CGFloat {
        return horizontalSizeClass == .regular ? (displayScale > 2 ? 16 : 14) : 12
    }
    
    private var iconSize: CGFloat {
        return horizontalSizeClass == .regular ? (displayScale > 2 ? 18 : 16) : 14
    }
    
    private var spacing: CGFloat {
        return horizontalSizeClass == .regular ? 12 : 8
    }
    
    private var padding: CGFloat {
        return horizontalSizeClass == .regular ? 12 : 8
    }
    
    var body: some View {
        VStack {
            if horizontalSizeClass == .regular {
                // Show sync status on larger watches
                if connectivityService.isReachable {
                    SyncStatusView(isSyncing: false)
                        .padding(.top, 4)
                }
            }
            
            if favoritesViewModel.isLoading {
                ProgressView()
                    .controlSize(.large)
                    .tint(AppColors.accent)
                    .padding(.top, 20)
            } else if favoritesViewModel.favoriteStops.isEmpty {
                EmptyFavoritesView()
            } else {
                List {
                    ForEach(favoritesViewModel.favoriteStops) { stop in
                        NavigationLink(destination: ArrivalsView(stop: stop)) {
                            StopRowView(stop: stop)
                                .padding(.vertical, 4)
                        }
                        .listRowBackground(Color.clear)
                    }
                    .onDelete(perform: favoritesViewModel.removeFavorite)
                    
                    if isEditing {
                        Button(action: {
                            withAnimation {
                                isEditing = false
                            }
                        }) {
                            Text("Done")
                                .font(.system(size: fontSize, weight: .medium))
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                        .buttonStyle(.bordered)
                        .tint(AppColors.accent)
                        .listRowBackground(Color.clear)
                    }
                }
                .listStyle(.carousel)
                .overlay(alignment: .topTrailing) {
                    if !isEditing && !favoritesViewModel.favoriteStops.isEmpty {
                        Button(action: {
                            withAnimation {
                                isEditing = true
                            }
                        }) {
                            Image(systemName: "pencil")
                                .font(.system(size: iconSize - 2, weight: .medium))
                                .padding(padding)
                                .background(
                                    Circle()
                                        .fill(AppColors.dynamicCardBackground(for: colorScheme))
                                        .shadow(color: Color.black.opacity(0.1), radius: 1, x: 0, y: 1)
                                )
                        }
                        .padding(.trailing, padding)
                        .padding(.top, padding)
                    }
                }
            }
        }
        .navigationTitle("Favorites")
        .refreshable {
            await favoritesViewModel.refreshFavorites()
        }
        .onAppear {
            // Request favorites from phone if syncing is enabled
            if UserDefaults.standard.bool(forKey: "syncWithPhone") {
                connectivityService.requestFavoritesFromPhone()
            }
        }
        .environment(\.colorScheme, darkMode ? .dark : colorScheme)
    }
}

struct EmptyFavoritesView: View {
    @EnvironmentObject private var connectivityService: WatchConnectivityService
    @Environment(\.colorScheme) var colorScheme
    
    // Dynamic sizing for different watch sizes
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @Environment(\.displayScale) var displayScale
    
    // Computed properties for responsive design
    private var iconSize: CGFloat {
        return horizontalSizeClass == .regular ? (displayScale > 2 ? 48 : 40) : 32
    }
    
    private var titleFontSize: CGFloat {
        return horizontalSizeClass == .regular ? (displayScale > 2 ? 18 : 16) : 14
    }
    
    private var subtitleFontSize: CGFloat {
        return horizontalSizeClass == .regular ? (displayScale > 2 ? 16 : 14) : 12
    }
    
    private var buttonFontSize: CGFloat {
        return horizontalSizeClass == .regular ? (displayScale > 2 ? 15 : 14) : 12
    }
    
    private var spacing: CGFloat {
        return horizontalSizeClass == .regular ? 16 : 12
    }
    
    var body: some View {
        VStack(spacing: spacing) {
            Image(systemName: "star.fill")
                .font(.system(size: iconSize))
                .foregroundColor(.yellow.opacity(0.7))
                .padding(.top, 20)
            
            Text("No favorite stops")
                .font(.system(size: titleFontSize, weight: .medium))
                .foregroundColor(AppColors.primaryText)
                .multilineTextAlignment(.center)
            
            Text("Add stops to your favorites for quick access")
                .font(.system(size: subtitleFontSize))
                .multilineTextAlignment(.center)
                .foregroundColor(AppColors.secondaryText)
                .padding(.horizontal)
            
            if connectivityService.isReachable {
                Button(action: {
                    connectivityService.requestFavoritesFromPhone()
                    HapticFeedback.medium.play()
                }) {
                    HStack {
                        Image(systemName: "iphone.and.arrow.forward")
                            .font(.system(size: buttonFontSize))
                        Text("Sync from iPhone")
                            .font(.system(size: buttonFontSize, weight: .medium))
                    }
                }
                .buttonStyle(.bordered)
                .tint(AppColors.accent)
                .padding(.top, 8)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(AppColors.dynamicCardBackground(for: colorScheme))
                .opacity(0.7)
        )
    }
}

struct SyncStatusView: View {
    let isSyncing: Bool
    @Environment(\.colorScheme) var colorScheme
    
    // Dynamic sizing for different watch sizes
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @Environment(\.displayScale) var displayScale
    
    // Computed properties for responsive design
    private var fontSize: CGFloat {
        return horizontalSizeClass == .regular ? (displayScale > 2 ? 13 : 12) : 10
    }
    
    private var iconSize: CGFloat {
        return horizontalSizeClass == .regular ? (displayScale > 2 ? 14 : 12) : 10
    }
    
    var body: some View {
        HStack {
            Image(systemName: isSyncing ? "arrow.triangle.2.circlepath" : "iphone.and.arrow.forward")
                .font(.system(size: iconSize))
                .if(isSyncing) { view in
                    view.symbolEffect(.bounce.byLayer, options: .repeating)
                }
            
            Text(isSyncing ? "Syncing with iPhone..." : "Connected to iPhone")
                .font(.system(size: fontSize))
        }
        .foregroundColor(AppColors.secondaryText)
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(colorScheme == .dark ? Color.gray.opacity(0.3) : AppColors.adaptiveGray(6))
        )
    }
}

extension View {
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}




struct FavoritesView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            FavoritesView()
                .environmentObject(FavoritesViewModel())
                .environmentObject(WatchConnectivityService.shared)
                .previewDevice("Apple Watch Series 7 (45mm)")
                .previewDisplayName("Light Mode")
            
            FavoritesView()
                .environmentObject(FavoritesViewModel())
                .environmentObject(WatchConnectivityService.shared)
                .previewDevice("Apple Watch Series 7 (45mm)")
                .previewDisplayName("Dark Mode")
                .environment(\.colorScheme, .dark)
        }
    }
}

