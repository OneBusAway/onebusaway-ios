//
//  HomeView.swift
//  OBAKit
//
//  Created by Prince Yadav on 06/03/25.
//

import SwiftUI
import CoreLocation
import WatchKit

struct HomeView: View {
    @EnvironmentObject private var stopsViewModel: StopsViewModel
    @EnvironmentObject private var favoritesViewModel: FavoritesViewModel
    @State private var isLoading = true
    @State private var selectedTab = 0
    @Environment(\.colorScheme) var colorScheme
    
    // Dynamic sizing for different watch sizes
    @Environment(\.sizeCategory) var sizeCategory
    @ScaledMetric var scale: CGFloat = 1
    
    private var fontSize: CGFloat {
        return scale > 1.2 ? 18 : (scale > 1.0 ? 16 : 14)
    }
    
    var body: some View {
        TabView(selection: $selectedTab) {
            NearbyStopsView()
                .tag(0)
                .tabItem {
                    Label("Nearby", systemImage: "location.fill")
                }
                .environmentObject(stopsViewModel)
            
            FavoritesView()
                .tag(1)
                .tabItem {
                    Label("Favorites", systemImage: "star.fill")
                }
                .environmentObject(favoritesViewModel)
            
            SettingsView()
                .tag(2)
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
        }
        .navigationTitle(tabTitle)
        .accentColor(.blue)
        .onAppear {
            stopsViewModel.requestLocationAndLoadNearbyStops()
            favoritesViewModel.loadFavorites()
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                isLoading = false
            }
        }
        .overlay {
            if isLoading {
                LoadingView()
            }
        }
    }
    
    private var tabTitle: String {
        switch selectedTab {
        case 0: return "Nearby"
        case 1: return "Favorites"
        case 2: return "Settings"
        default: return "OneBusAway"
        }
    }
}

struct NearbyStopsView: View {
    @EnvironmentObject private var stopsViewModel: StopsViewModel
    @State private var searchText = ""
    @Environment(\.colorScheme) var colorScheme
    @ScaledMetric var scale: CGFloat = 1
    
    private var filteredStops: [Stop] {
        if searchText.isEmpty {
            return stopsViewModel.nearbyStops
        } else {
            return stopsViewModel.nearbyStops.filter { stop in
                stop.name.lowercased().contains(searchText.lowercased()) ||
                stop.routes.joined(separator: ", ").lowercased().contains(searchText.lowercased())
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            if WKInterfaceDevice.current().screenBounds.width > 180 {
                // Only show search on larger watches
                SearchBar(text: $searchText)
                    .padding(.horizontal)
                    .padding(.top)
            }
            
            List {
                if stopsViewModel.isLoading {
                    HStack {
                        Spacer()
                        ProgressView()
                            .controlSize(.large)
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                } else if let error = stopsViewModel.errorMessage {
                    ErrorView(
                        message: error,
                        retryAction: {
                            stopsViewModel.requestLocationAndLoadNearbyStops()
                        }
                    )
                    .listRowBackground(Color.clear)
                } else if filteredStops.isEmpty {
                    EmptyStateView(
                        icon: "location.slash.fill",
                        title: searchText.isEmpty ? "No stops found nearby" : "No matching stops",
                        message: "Try adjusting your search or location"
                    )
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(filteredStops) { stop in
                        NavigationLink(destination: ArrivalsView(stop: stop)) {
                            StopRowView(stop: stop)
                        }
                        .listRowBackground(Color.clear)
                    }
                }
            }
            .listStyle(.carousel)
            .refreshable {
                await stopsViewModel.refreshNearbyStops()
            }
        }
    }
}

struct ErrorView: View {
    let message: String
    let retryAction: () -> Void
    
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 32))
                .foregroundColor(.red)
            
            Text("Network Error")
                .font(.headline)
            
            Text(message)
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal)
            
            Button(action: retryAction) {
                Text("Refresh")
                    .font(.system(.body, design: .rounded))
                    .fontWeight(.medium)
            }
            .buttonStyle(.bordered)
            .tint(.blue)
        }
        .padding()
        .frame(maxWidth: .infinity)
    }
}

struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 32))
                .foregroundColor(.secondary)
            
            Text(title)
                .font(.headline)
            
            Text(message)
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal)
        }
        .padding()
        .frame(maxWidth: .infinity)
    }
}

struct SearchBar: View {
    @Binding var text: String
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            
            TextField("Search", text: $text)
                .textFieldStyle(PlainTextFieldStyle())
            
            if !text.isEmpty {
                Button(action: { text = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(8)
        .background(colorScheme == .dark ? Color.black.opacity(0.3) : Color.gray.opacity(0.2))
        .cornerRadius(10)
    }
}

struct StopRowView: View {
    let stop: Stop
    
    // Dynamic sizing for different watch sizes
    @Environment(\.sizeCategory) var sizeCategory
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @Environment(\.displayScale) var displayScale
    @Environment(\.colorScheme) var colorScheme
    
    // Computed properties for responsive design
    private var titleFontSize: CGFloat {
        return horizontalSizeClass == .regular ? (displayScale > 2 ? 16 : 15) : 14
    }
    
    private var subtitleFontSize: CGFloat {
        return horizontalSizeClass == .regular ? (displayScale > 2 ? 14 : 13) : 12
    }
    
    private var routeFontSize: CGFloat {
        return horizontalSizeClass == .regular ? (displayScale > 2 ? 12 : 11) : 10
    }
    
    private var spacing: CGFloat {
        return horizontalSizeClass == .regular ? (displayScale > 2 ? 6 : 5) : 4
    }
    
    private var routeSpacing: CGFloat {
        return horizontalSizeClass == .regular ? 4 : 3
    }
    
    private var routePadding: CGFloat {
        return horizontalSizeClass == .regular ? 6 : 4
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            Text(stop.name)
                .font(.system(size: titleFontSize, weight: .semibold))
                .foregroundColor(AppColors.primaryText)
                .lineLimit(1)
            
            Text(stop.direction)
                .font(.system(size: subtitleFontSize))
                .foregroundColor(AppColors.secondaryText)
                .lineLimit(1)
            
            HStack(spacing: routeSpacing) {
                ForEach(stop.routes.prefix(3), id: \.self) { route in
                    Text(route)
                        .font(.system(size: routeFontSize, weight: .medium))
                        .padding(.horizontal, routePadding)
                        .padding(.vertical, 2)
                        .background(AppColors.accent)
                        .foregroundColor(.white)
                        .cornerRadius(4)
                }
                
                if stop.routes.count > 3 {
                    Text("+\(stop.routes.count - 3)")
                        .font(.system(size: routeFontSize))
                        .foregroundColor(AppColors.secondaryText)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct HomeView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            // Preview for smaller watches (38mm, 40mm)
            HomeView()
                .environmentObject(StopsViewModel())
                .environmentObject(FavoritesViewModel())
                .previewDevice("Apple Watch Series 4 (40mm)")
                .previewDisplayName("Series 4 (40mm)")
            
            // Preview for larger watches (44mm, 45mm)
            HomeView()
                .environmentObject(StopsViewModel())
                .environmentObject(FavoritesViewModel())
                .previewDevice("Apple Watch Series 7 (45mm)")
                .previewDisplayName("Series 7 (45mm)")
            
            // Preview for Apple Watch Ultra
            HomeView()
                .environmentObject(StopsViewModel())
                .environmentObject(FavoritesViewModel())
                .previewDevice("Apple Watch Ultra")
                .previewDisplayName("Apple Watch Ultra")
        }
    }
}

