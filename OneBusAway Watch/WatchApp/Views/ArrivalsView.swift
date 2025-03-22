//
//  ArrivalsView.swift
//  OBAKit
//
//  Created by Prince Yadav on 06/03/25.
//


import SwiftUI

struct ArrivalsView: View {
    let stop: Stop
    @StateObject private var viewModel = ArrivalsViewModel()
    @AppStorage("darkMode") private var darkMode = false
    
    // Dynamic sizing for different watch sizes
    @Environment(\.sizeCategory) var sizeCategory
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @Environment(\.displayScale) var displayScale
    @Environment(\.colorScheme) var colorScheme
    
    // Computed properties for responsive design
    private var fontSize: CGFloat {
        return horizontalSizeClass == .regular ? (displayScale > 2 ? 16 : 14) : 12
    }
    
    private var headerFontSize: CGFloat {
        return horizontalSizeClass == .regular ? (displayScale > 2 ? 18 : 16) : 14
    }
    
    private var spacing: CGFloat {
        return horizontalSizeClass == .regular ? 12 : 8
    }
    
    private var padding: CGFloat {
        return horizontalSizeClass == .regular ? 16 : 12
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: spacing) {
                // Stop information header
                StopHeaderView(stop: stop)
                
                // Arrivals content
                if viewModel.isLoading {
                    ProgressView()
                        .controlSize(.large)
                        .tint(AppColors.accent)
                        .padding(.top, padding)
                } else if viewModel.arrivals.isEmpty {
                    EmptyArrivalsView()
                } else {
                    // Group arrivals by route for better organization
                    ArrivalsListView(arrivals: viewModel.arrivals)
                }
                
                // Favorite button
                FavoriteButton(
                    isFavorite: viewModel.isFavorite,
                    action: { viewModel.toggleFavorite(stop: stop) }
                )
                .padding(.top, spacing)
                
                // Last updated timestamp
                if !viewModel.isLoading && !viewModel.arrivals.isEmpty {
                    HStack {
                        Image(systemName: "clock")
                            .font(.system(size: fontSize - 4))
                            .foregroundColor(AppColors.tertiaryText)
                        
                        Text("Updated: \(formattedUpdateTime)")
                            .font(.system(size: fontSize - 2))
                            .foregroundColor(AppColors.tertiaryText)
                    }
                    .padding(.top, 4)
                }
            }
            .padding(.horizontal, padding / 2)
        }
        .navigationTitle("Arrivals")
        .onAppear {
            viewModel.loadArrivals(for: stop.id)
            viewModel.checkIfFavorite(stop: stop)
            
            // Set up auto-refresh timer
            viewModel.startAutoRefresh()
        }
        .onDisappear {
            viewModel.stopAutoRefresh()
        }
        .refreshable {
            await viewModel.refreshArrivals()
        }
        .environment(\.colorScheme, darkMode ? .dark : colorScheme)
    }
    
    private var formattedUpdateTime: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: viewModel.lastUpdated)
    }
}

struct StopHeaderView: View {
    let stop: Stop
    
    // Dynamic sizing for different watch sizes
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @Environment(\.displayScale) var displayScale
    @Environment(\.colorScheme) var colorScheme
    
    // Computed properties for responsive design
    private var titleFontSize: CGFloat {
        return horizontalSizeClass == .regular ? (displayScale > 2 ? 18 : 16) : 14
    }
    
    private var subtitleFontSize: CGFloat {
        return horizontalSizeClass == .regular ? (displayScale > 2 ? 16 : 14) : 12
    }
    
    private var routeFontSize: CGFloat {
        return horizontalSizeClass == .regular ? (displayScale > 2 ? 12 : 11) : 10
    }
    
    private var spacing: CGFloat {
        return horizontalSizeClass == .regular ? 6 : 4
    }
    
    private var padding: CGFloat {
        return horizontalSizeClass == .regular ? 12 : 8
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            Text(stop.name)
                .font(.system(size: titleFontSize, weight: .bold))
                .foregroundColor(AppColors.primaryText)
                .lineLimit(1)
            
            Text(stop.direction)
                .font(.system(size: subtitleFontSize))
                .foregroundColor(AppColors.secondaryText)
            
            HStack(spacing: 4) {
                ForEach(stop.routes.prefix(5), id: \.self) { route in
                    Text(route)
                        .font(.system(size: routeFontSize, weight: .medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(AppColors.accent)
                        .foregroundColor(.white)
                        .cornerRadius(4)
                }
                
                if stop.routes.count > 5 {
                    Text("+\(stop.routes.count - 5)")
                        .font(.system(size: routeFontSize))
                        .foregroundColor(AppColors.secondaryText)
                }
            }
            
            if let distance = stop.formattedDistance {
                HStack(spacing: 4) {
                    Image(systemName: "location.fill")
                        .font(.system(size: routeFontSize))
                        .foregroundColor(AppColors.tertiaryText)
                    
                    Text(distance)
                        .font(.system(size: routeFontSize))
                        .foregroundColor(AppColors.tertiaryText)
                }
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, padding)
        .padding(.horizontal, padding)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(AppColors.dynamicCardBackground(for: colorScheme))
        )
        .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
    }
}

struct EmptyArrivalsView: View {
    // Dynamic sizing for different watch sizes
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @Environment(\.displayScale) var displayScale
    @Environment(\.colorScheme) var colorScheme
    
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
    
    private var spacing: CGFloat {
        return horizontalSizeClass == .regular ? 12 : 8
    }
    
    var body: some View {
        VStack(spacing: spacing) {
            Image(systemName: "bus.fill")
                .font(.system(size: iconSize))
                .foregroundColor(AppColors.secondaryText)
                .padding(.top, 20)
            
            Text("No upcoming arrivals")
                .font(.system(size: titleFontSize, weight: .medium))
                .multilineTextAlignment(.center)
                .foregroundColor(AppColors.secondaryText)
            
            Text("Check back later for updates")
                .font(.system(size: subtitleFontSize))
                .multilineTextAlignment(.center)
                .foregroundColor(AppColors.tertiaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(AppColors.dynamicCardBackground(for: colorScheme))
                .opacity(0.7)
        )
    }
}

struct ArrivalsListView: View {
    let arrivals: [Arrival]
    
    // Dynamic sizing for different watch sizes
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @Environment(\.displayScale) var displayScale
    @Environment(\.colorScheme) var colorScheme
    
    // Computed properties for responsive design
    private var spacing: CGFloat {
        return horizontalSizeClass == .regular ? 12 : 8
    }
    
    // Group arrivals by route for better organization
    private var groupedArrivals: [String: [Arrival]] {
        Dictionary(grouping: arrivals) { $0.routeShortName }
    }
    
    var body: some View {
        VStack(spacing: spacing) {
            ForEach(groupedArrivals.keys.sorted(), id: \.self) { routeKey in
                if let routeArrivals = groupedArrivals[routeKey] {
                    RouteArrivalsView(routeName: routeKey, arrivals: routeArrivals)
                }
            }
        }
    }
}

struct RouteArrivalsView: View {
    let routeName: String
    let arrivals: [Arrival]
    
    // Dynamic sizing for different watch sizes
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @Environment(\.displayScale) var displayScale
    @Environment(\.colorScheme) var colorScheme
    
    // Computed properties for responsive design
    private var titleFontSize: CGFloat {
        return horizontalSizeClass == .regular ? (displayScale > 2 ? 16 : 14) : 12
    }
    
    private var subtitleFontSize: CGFloat {
        return horizontalSizeClass == .regular ? (displayScale > 2 ? 14 : 12) : 10
    }
    
    private var spacing: CGFloat {
        return horizontalSizeClass == .regular ? 8 : 6
    }
    
    private var padding: CGFloat {
        return horizontalSizeClass == .regular ? 10 : 8
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            // Route header
            HStack {
                Text(routeName)
                    .font(.system(size: titleFontSize, weight: .bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(arrivals.first?.routeColor ?? AppColors.accent)
                    .foregroundColor(.white)
                    .cornerRadius(6)
                
                Text(arrivals.first?.headsign ?? "")
                    .font(.system(size: subtitleFontSize))
                    .lineLimit(1)
                    .foregroundColor(AppColors.secondaryText)
            }
            
            // Arrival times
            VStack(spacing: spacing - 2) {
                ForEach(arrivals.prefix(3)) { arrival in
                    ArrivalRowView(arrival: arrival)
                }
            }
        }
        .padding(padding)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(AppColors.dynamicCardBackground(for: colorScheme))
        )
        .shadow(color: Color.black.opacity(0.05), radius: 1, x: 0, y: 1)
    }
}

struct ArrivalRowView: View {
    let arrival: Arrival
    
    // Dynamic sizing for different watch sizes
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @Environment(\.displayScale) var displayScale
    @Environment(\.colorScheme) var colorScheme
    
    // Computed properties for responsive design
    private var fontSize: CGFloat {
        return horizontalSizeClass == .regular ? (displayScale > 2 ? 16 : 14) : 12
    }
    
    private var indicatorSize: CGFloat {
        return horizontalSizeClass == .regular ? 8 : 6
    }
    
    var body: some View {
        HStack {
            // Status indicator
            Circle()
                .fill(arrival.isLate ? AppColors.error : AppColors.success)
                .frame(width: indicatorSize, height: indicatorSize)
            
            // Arrival time
            Text(arrival.formattedArrivalTime)
                .font(.system(size: fontSize, weight: .medium))
                .foregroundColor(AppColors.primaryText)
            
            Spacer()
            
            // Minutes until arrival
            Text(arrival.minutesUntilArrival)
                .font(.system(size: fontSize, weight: .bold))
                .foregroundColor(arrival.isLate ? AppColors.error : AppColors.success)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(arrival.isLate ?
                              AppColors.error.opacity(0.2) :
                              AppColors.success.opacity(0.2))
                )
        }
    }
}

struct FavoriteButton: View {
    let isFavorite: Bool
    let action: () -> Void
    
    // Dynamic sizing for different watch sizes
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @Environment(\.displayScale) var displayScale
    @Environment(\.colorScheme) var colorScheme
    
    // Computed properties for responsive design
    private var fontSize: CGFloat {
        return horizontalSizeClass == .regular ? (displayScale > 2 ? 15 : 14) : 12
    }
    
    private var iconSize: CGFloat {
        return horizontalSizeClass == .regular ? (displayScale > 2 ? 16 : 14) : 12
    }
    
    private var padding: CGFloat {
        return horizontalSizeClass == .regular ? 10 : 8
    }
    
    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: isFavorite ? "star.fill" : "star")
                    .font(.system(size: iconSize))
                Text(isFavorite ? "Remove from Favorites" : "Add to Favorites")
                    .font(.system(size: fontSize, weight: .medium))
            }
            .padding(.vertical, padding)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(FavoriteButtonStyle(isFavorite: isFavorite))
    }
}

struct FavoriteButtonStyle: ButtonStyle {
    let isFavorite: Bool
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isFavorite ?
                          Color.yellow.opacity(configuration.isPressed ? 0.7 : 0.9) :
                          AppColors.accent.opacity(configuration.isPressed ? 0.7 : 0.9))
            )
            .foregroundColor(.white)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.2), value: configuration.isPressed)
    }
}

struct ArrivalsView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            // Preview for smaller watches (38mm, 40mm)
            ArrivalsView(stop: Stop.example)
                .previewDevice("Apple Watch Series 4 (40mm)")
                .previewDisplayName("Series 4 (40mm)")
            
            // Preview for larger watches (44mm, 45mm)
            ArrivalsView(stop: Stop.example)
                .previewDevice("Apple Watch Series 7 (45mm)")
                .previewDisplayName("Series 7 (45mm)")
                .environment(\.colorScheme, .dark)
        }
    }
}

