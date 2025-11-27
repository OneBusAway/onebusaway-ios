//
//  StopHeaderInfoView.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import UIKit
import OBAKitCore

// MARK: - OBAListView Integration

/// List view item for hosting the SwiftUI stop header
struct StopSwiftUIHeaderItem: OBAListViewItem {
    var configuration: OBAListViewItemConfiguration {
        return .custom(StopSwiftUIHeaderContentConfiguration(viewModel: viewModel, actions: actions))
    }

    static var customCellType: OBAListViewCell.Type? {
        return StopSwiftUIHeaderCollectionCell.self
    }

    var onSelectAction: OBAListViewAction<StopSwiftUIHeaderItem>?

    let id: String = "stop_swiftui_header"
    let viewModel: StopHeaderViewModel
    let actions: StopHeaderActions

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(viewModel.lastUpdated)
        hasher.combine(viewModel.isFiltered)
        hasher.combine(viewModel.sortType)
    }

    static func == (lhs: StopSwiftUIHeaderItem, rhs: StopSwiftUIHeaderItem) -> Bool {
        return lhs.id == rhs.id
    }
}

/// Actions container for the stop header
struct StopHeaderActions {
    let onShowAllRoutes: () -> Void
    let onShowFilteredRoutes: () -> Void
    let onAddBookmark: () -> Void
    let onShowServiceAlerts: () -> Void
    let onShowNearbyStops: () -> Void
    let onWalkingDirectionsApple: () -> Void
    let onWalkingDirectionsGoogle: (() -> Void)?
    let onSortByTime: () -> Void
    let onSortByRoute: () -> Void
    let onReportProblem: () -> Void
}

struct StopSwiftUIHeaderContentConfiguration: OBAContentConfiguration {
    let viewModel: StopHeaderViewModel
    let actions: StopHeaderActions
    var formatters: Formatters?

    var obaContentView: (OBAContentView & ReuseIdentifierProviding).Type {
        return StopSwiftUIHeaderCollectionCell.self
    }
}

/// Collection cell that hosts the SwiftUI header view
class StopSwiftUIHeaderCollectionCell: OBAListViewCell {
    private var hostingController: UIHostingController<StopHeaderInfoView>?

    override func apply(_ config: OBAContentConfiguration) {
        guard let config = config as? StopSwiftUIHeaderContentConfiguration else { return }

        // Remove existing hosting controller
        hostingController?.view.removeFromSuperview()
        hostingController?.removeFromParent()

        // Create SwiftUI view
        let headerView = StopHeaderInfoView(
            viewModel: config.viewModel,
            onShowAllRoutes: config.actions.onShowAllRoutes,
            onShowFilteredRoutes: config.actions.onShowFilteredRoutes,
            onAddBookmark: config.actions.onAddBookmark,
            onShowServiceAlerts: config.actions.onShowServiceAlerts,
            onShowNearbyStops: config.actions.onShowNearbyStops,
            onWalkingDirectionsApple: config.actions.onWalkingDirectionsApple,
            onWalkingDirectionsGoogle: config.actions.onWalkingDirectionsGoogle,
            onSortByTime: config.actions.onSortByTime,
            onSortByRoute: config.actions.onSortByRoute,
            onReportProblem: config.actions.onReportProblem
        )

        let hosting = UIHostingController(rootView: headerView)
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        hosting.view.backgroundColor = .clear

        contentView.addSubview(hosting.view)
        NSLayoutConstraint.activate([
            hosting.view.topAnchor.constraint(equalTo: contentView.topAnchor),
            hosting.view.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])

        hostingController = hosting
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        hostingController?.view.removeFromSuperview()
        hostingController = nil
    }
}

// MARK: - View Model

/// Observable view model for the stop header, enabling reactive updates
class StopHeaderViewModel: ObservableObject {
    @Published var lastUpdated: Date?
    @Published var isFiltered: Bool = false
    @Published var sortType: StopSort = .time
    @Published var hasHiddenRoutes: Bool = false
    @Published var serviceAlertsCount: Int = 0

    let stop: Stop
    let formatters: Formatters

    init(stop: Stop, formatters: Formatters) {
        self.stop = stop
        self.formatters = formatters
    }

    var formattedUpdateTime: String {
        guard let lastUpdated else { return "Now" }
        return formatters.timeAgoInWords(date: lastUpdated)
    }

    var formattedStopInfo: String {
        Formatters.formattedCodeAndDirection(stop: stop)
    }

    var formattedRoutes: String {
        Formatters.formattedRoutes(stop.routes ?? []) ?? ""
    }

    var filterButtonTitle: String {
        hasHiddenRoutes && isFiltered ? "Filter (On)" : "Filter"
    }

    var filterButtonIcon: String {
        hasHiddenRoutes && isFiltered ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle"
    }
}

// MARK: - SwiftUI View

/// A SwiftUI header view displaying stop information and action menus
struct StopHeaderInfoView: View {
    @ObservedObject var viewModel: StopHeaderViewModel

    // Action callbacks
    let onShowAllRoutes: () -> Void
    let onShowFilteredRoutes: () -> Void
    let onAddBookmark: () -> Void
    let onShowServiceAlerts: () -> Void
    let onShowNearbyStops: () -> Void
    let onWalkingDirectionsApple: () -> Void
    let onWalkingDirectionsGoogle: (() -> Void)?
    let onSortByTime: () -> Void
    let onSortByRoute: () -> Void
    let onReportProblem: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Row 2: Updated time
            Text("Updated: \(viewModel.formattedUpdateTime)")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            // Row 3: Stop ID - Direction
            Text(viewModel.formattedStopInfo)
                .font(.subheadline)

            // Row 4: Routes
            if !viewModel.formattedRoutes.isEmpty {
                Text("Routes: \(viewModel.formattedRoutes)")
                    .font(.subheadline)
            }

            // Row 5: Filter and Options menus
            HStack(spacing: 12) {
                filterMenu
                optionsMenu
            }
            .padding(.top, 4)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Filter Menu

    private var filterMenu: some View {
        Menu {
            Button {
                onShowAllRoutes()
            } label: {
                if !viewModel.isFiltered || !viewModel.hasHiddenRoutes {
                    Label("All Routes", systemImage: "checkmark")
                } else {
                    Text("All Routes")
                }
            }

            Button {
                onShowFilteredRoutes()
            } label: {
                if viewModel.isFiltered && viewModel.hasHiddenRoutes {
                    Label("Filtered Routes", systemImage: "checkmark")
                } else {
                    Text("Filtered Routes")
                }
            }
        } label: {
            Label(viewModel.filterButtonTitle, systemImage: viewModel.filterButtonIcon)
        }
        .buttonStyle(.bordered)
    }

    // MARK: - Options Menu

    private var optionsMenu: some View {
        Menu {
            // File section
            Section {
                Button {
                    onAddBookmark()
                } label: {
                    Label("Add Bookmark", systemImage: "bookmark")
                }

                Button {
                    onShowServiceAlerts()
                } label: {
                    Label("Service Alerts", systemImage: "exclamationmark.circle")
                }
                .disabled(viewModel.serviceAlertsCount == 0)
            }

            // Location section
            Section {
                Button {
                    onShowNearbyStops()
                } label: {
                    Label("Nearby Stops", systemImage: "location")
                }

                // Walking directions submenu
                Menu {
                    Button("Apple Maps") {
                        onWalkingDirectionsApple()
                    }

                    if let onGoogle = onWalkingDirectionsGoogle {
                        Button("Google Maps") {
                            onGoogle()
                        }
                    }
                } label: {
                    Label("Walking Directions", systemImage: "figure.walk")
                }
            }

            // Sort section
            Section {
                Menu {
                    Button {
                        onSortByTime()
                    } label: {
                        if viewModel.sortType == .time {
                            Label("Sort by time", systemImage: "checkmark")
                        } else {
                            Text("Sort by time")
                        }
                    }

                    Button {
                        onSortByRoute()
                    } label: {
                        if viewModel.sortType == .route {
                            Label("Sort by route", systemImage: "checkmark")
                        } else {
                            Text("Sort by route")
                        }
                    }
                } label: {
                    Label("Sort By", systemImage: "arrow.up.arrow.down")
                }
            }

            // Help section
            Section {
                Button {
                    onReportProblem()
                } label: {
                    Label("Report a Problem", systemImage: "exclamationmark.bubble")
                }
            }
        } label: {
            Label("Options", systemImage: "ellipsis.circle")
        }
        .buttonStyle(.bordered)
    }
}
