//
//  NearbyStopsListViewController.swift
//  OBAKit
//
//  Created by Alan Chu on 4/4/23.
//

import Foundation
import SwiftUI
import MapKit
import OBAKitCore

protocol NearbyStopsListDelegate: AnyObject {
    func didSelect(stopID: Stop.ID)
    func didSelect(agencyAlert: AgencyAlert)

    func previewViewController(for stopID: Stop.ID) -> UIViewController?
    func commitPreviewViewController(_ viewController: UIViewController)
}

protocol NearbyStopsListDataSource: AnyObject {
    var highSeverityAlerts: [AgencyAlert] { get }
    var stops: [Stop] { get }
}

/// Displays a list of stops and high-priority alerts.
class NearbyStopsListViewController: UIViewController, UICollectionViewDelegate, Scrollable {

    var onExpandSearchTapped: (() -> Void)?

    // MARK: - Type definitions
    private enum Section: Hashable {
        case alert
        case nearbyStops

        public var localizedTitle: String {
            switch self {
            case .alert:
                return Strings.serviceAlerts
            case .nearbyStops:
                return OBALoc("nearby_stops_controller.title", value: "Nearby Stops", comment: "The title of the Nearby Stops controller.")
            }
        }
    }

    private struct Item: Hashable {
        // swiftlint:disable:next nesting
        enum ItemType: Hashable {
            case header
            case stop(stopID: Stop.ID)
            case alert(AgencyAlert)
        }

        let title: String
        let subtitle: String?
        let image: UIImage?
        let type: ItemType

        init(headerForSection section: Section) {
            self.title = section.localizedTitle
            self.subtitle = nil
            self.image = nil
            self.type = .header
        }

        init(_ stop: Stop) {
            self.title = stop.nameWithLocalizedDirectionAbbreviation
            self.subtitle = stop.subtitle
            self.image = Icons.transportIcon(from: stop.prioritizedRouteTypeForDisplay)
            self.type = .stop(stopID: stop.id)
        }

        init(_ alert: AgencyAlert) {
            self.title = alert.title(forLocale: .current) ?? ""
            self.subtitle = nil
            self.image = Icons.unreadAlert
            self.type = .alert(alert)
        }
    }

    private typealias SectionType = Section
    private typealias ItemType = Item

    // MARK: - Scrollable methods
    var scrollView: UIScrollView {
        collectionView
    }

    // MARK: - Data management
    public weak var delegate: NearbyStopsListDelegate?
    public weak var dataSource: NearbyStopsListDataSource?

    // MARK: - UICollectionView properties
    private var collectionView: UICollectionView!
    private var diffableDataSource: UICollectionViewDiffableDataSource<Section, ItemType>!
    private var headerCellRegistration: UICollectionView.CellRegistration<UICollectionViewListCell, ItemType>!
    private var cellRegistration: UICollectionView.CellRegistration<UICollectionViewListCell, ItemType>!
    private var emptyStateHostingController: UIViewController?

    // MARK: - UIViewController lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()

        self.headerCellRegistration = UICollectionView.CellRegistration<UICollectionViewListCell, ItemType> { cell, _, item in
            var config = cell.defaultContentConfiguration()
            config.text = item.title
            config.textProperties.font = .preferredFont(forTextStyle: .headline)
            cell.contentConfiguration = config
        }

        self.cellRegistration = UICollectionView.CellRegistration<UICollectionViewListCell, ItemType> { cell, _, item in
            var config = cell.defaultContentConfiguration()
            config.text = item.title
            config.secondaryText = item.subtitle
            config.image = item.image
            config.imageProperties.tintColor = .label
            config.imageProperties.maximumSize = CGSize(width: 24, height: 24)

            cell.contentConfiguration = config
        }

        self.collectionView = .init(frame: .zero, collectionViewLayout: createLayout())
        self.collectionView.backgroundColor = .clear
        self.diffableDataSource = .init(collectionView: collectionView, cellProvider: cellFor(_:indexPath:itemIdentifier:))
        self.collectionView.dataSource = diffableDataSource
        self.collectionView.delegate = self

        self.view.addSubview(collectionView)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.pinToSuperview(.edges)
    }

    private func createLayout() -> UICollectionViewLayout {
        return UICollectionViewCompositionalLayout { _, layoutEnvironment in
            var config = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
            config.backgroundColor = .clear
            config.headerMode = .firstItemInSection

            return NSCollectionLayoutSection.readableContentGuideList(using: config, layoutEnvironment: layoutEnvironment)
        }
    }

    private func cellFor(_ collectionView: UICollectionView, indexPath: IndexPath, itemIdentifier: ItemType) -> UICollectionViewCell? {
        switch itemIdentifier.type {
        case .header:
            return collectionView.dequeueConfiguredReusableCell(using: headerCellRegistration, for: indexPath, item: itemIdentifier)
        case .alert, .stop:
            return collectionView.dequeueConfiguredReusableCell(using: cellRegistration, for: indexPath, item: itemIdentifier)
        }
    }

    private func toggleEmptyDataView(isShowing: Bool) {
        if isShowing {
            let emptyStateView = VStack(spacing: 20) {
                VStack(spacing: 8) {
                    Text(OBALoc("nearby_controller.empty_set.title", value: "No Nearby Stops", comment: "Title for the empty set indicator on the Nearby controller"))
                        .font(.headline)
                        .foregroundColor(.primary)

                    Text(OBALoc("nearby_controller.empty_set.body", value: "Zoom out or pan around to find some stops.", comment: "Body for the empty set indicator on the Nearby controller."))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 40)

                TaskButton(OBALoc("nearby_controller.empty_set.button", value: "Search Wider Area", comment: "Button to search wider area"), actionOptions: []) { [weak self] in
                    self?.onExpandSearchTapped?()
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(ThemeColors.shared.brand))
                .clipShape(Capsule())
            }

            let hostingController = UIHostingController(rootView: emptyStateView)
            hostingController.view.backgroundColor = .clear

            self.addChild(hostingController)
            collectionView.backgroundView = hostingController.view
            hostingController.didMove(toParent: self)

            self.emptyStateHostingController = hostingController
        } else {
            if let hostingController = emptyStateHostingController {
                hostingController.willMove(toParent: nil)
                hostingController.view.removeFromSuperview()
                hostingController.removeFromParent()
                self.emptyStateHostingController = nil
            }
            collectionView.backgroundView = nil
        }
    }

    @MainActor
    public func updateList() {
        guard let dataSource else {
            #if DEBUG
            preconditionFailure("dataSource must be set.")
            #else
            return
            #endif
        }

        var sections: [SectionType] = []

        // Add alerts, if any.
        var alertSectionSnapshot: NSDiffableDataSourceSectionSnapshot<ItemType>?
        let alerts = dataSource.highSeverityAlerts
        if !alerts.isEmpty {
            var sectionSnapshot = NSDiffableDataSourceSectionSnapshot<ItemType>()
            let alertHeader = Item(headerForSection: .alert)
            sectionSnapshot.append([alertHeader])

            let items = alerts.map(Item.init)
            sectionSnapshot.append(items)

            alertSectionSnapshot = sectionSnapshot
            sections.append(.alert)
        }

        // Add nearby stops.
        var stopsSectionSnapshot: NSDiffableDataSourceSectionSnapshot<ItemType>?
        let stops = dataSource.stops
        if !stops.isEmpty {
            var sectionSnapshot = NSDiffableDataSourceSectionSnapshot<ItemType>()

            let nearbyStopsHeader = Item(headerForSection: .nearbyStops)
            sectionSnapshot.append([nearbyStopsHeader])

            let nearbyStops = dataSource.stops.map(Item.init)
            sectionSnapshot.append(nearbyStops)

            stopsSectionSnapshot = sectionSnapshot

            sections.append(.nearbyStops)
        }

        var snapshot = NSDiffableDataSourceSnapshot<SectionType, ItemType>()
        snapshot.appendSections(sections)
        self.diffableDataSource.apply(snapshot)

        if let alertSectionSnapshot {
            self.diffableDataSource.apply(alertSectionSnapshot, to: .alert, animatingDifferences: true)
        }

        if let stopsSectionSnapshot {
            self.diffableDataSource.apply(stopsSectionSnapshot, to: .nearbyStops, animatingDifferences: true)
        }

        toggleEmptyDataView(isShowing: sections.isEmpty)
    }

    // MARK: - UICollectionViewDelegate methods
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let delegate, let item = diffableDataSource.itemIdentifier(for: indexPath) else {
            return
        }

        switch item.type {
        case .stop(let id):
            delegate.didSelect(stopID: id)
        case .alert(let alert):
            delegate.didSelect(agencyAlert: alert)
        case .header:
            // Do nothing.
            return
        }
    }

    func collectionView(_ collectionView: UICollectionView, contextMenuConfigurationForItemsAt indexPaths: [IndexPath], point: CGPoint) -> UIContextMenuConfiguration? {
        guard let delegate else {
            return nil
        }

        // Supports only single selection.
        guard indexPaths.count == 1, let indexPath = indexPaths.first else {
            return nil
        }

        guard let item = diffableDataSource.itemIdentifier(for: indexPath) else {
            return nil
        }

        guard case let .stop(stopID) = item.type else {
            return nil
        }

        guard let viewController = delegate.previewViewController(for: stopID) else {
            return nil
        }

        if let previewable = viewController as? Previewable {
            previewable.enterPreviewMode()
        }

        return UIContextMenuConfiguration(previewProvider: {
            viewController
        }, actionProvider: nil)
    }

    func collectionView(_ collectionView: UICollectionView, willPerformPreviewActionForMenuWith configuration: UIContextMenuConfiguration, animator: UIContextMenuInteractionCommitAnimating) {
        guard let viewController = animator.previewViewController else {
            return
        }

        animator.addCompletion { [weak self] in
            guard let self else {
                return
            }

            if let previewable = viewController as? Previewable {
                previewable.exitPreviewMode()
            }

            self.delegate?.commitPreviewViewController(viewController)
        }
    }
}
