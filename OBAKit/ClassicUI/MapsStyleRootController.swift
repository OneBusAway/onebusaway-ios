//
//  MapsStyleRootController.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import UIKit
import MapKit
import OBAKitCore

// MARK: - Protocol

/// Abstracts the root controller so ViewRouter works with both
/// ClassicApplicationRootController and MapsStyleRootController.
@MainActor
public protocol ApplicationRootController: UIViewController {
    func navigate(to destination: ClassicApplicationRootController.Page)
}

// MARK: - MapsStyleRootController

/// A Maps-style root controller where the map fills the entire screen and a
/// persistent bottom sheet (Apple Maps style) floats above it.
///
/// Sheet detents:
///   - compact  (~90pt)  — grab handle + search pill only, map fully interactive
///   - medium   (~50%)   — search pill + scrollable bookmarks/recent content
///   - large    (full)   — full-screen content
@objc(OBAMapsStyleRootController)
public class MapsStyleRootController: UIViewController, ApplicationRootController {

    // MARK: - Child controllers

    let mapController: MapViewController
    let moreController: MoreViewController

    private let application: Application

    /// The persistent Apple Maps-style bottom sheet.
    private lazy var bottomSheet = MapBottomSheetViewController(application: application)
    /// Nav controller wrapping the bottom sheet so embedded VCs can push onto it.
    private lazy var bottomSheetNav: UINavigationController = {
        let nav = UINavigationController(rootViewController: bottomSheet)
        nav.setNavigationBarHidden(true, animated: false)
        nav.delegate = self
        return nav
    }()

    // MARK: - Compact detent height
    // grab handle (5) + gaps (6+6) + search pill (40) + bottom safe area padding = ~75pt
    private static let compactDetentHeight: CGFloat = 75
    private static let compactDetentID = UISheetPresentationController.Detent.Identifier("compact")

    // MARK: - Init

    @objc public init(application: Application) {
        self.application = application
        self.mapController = MapViewController(application: application)
        self.moreController = MoreViewController(application: application)

        super.init(nibName: nil, bundle: nil)

        application.viewRouter.rootController = self
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - UIViewController

    public override func viewDidLoad() {
        super.viewDidLoad()

        embedMapController()
        presentBottomSheet()

        // When search results are shown on the map, exit search mode in the sheet.
        mapController.onSearchDismissed = { [weak self] in
            self?.bottomSheet.exitSearchMode()
            self?.snapSheetToCompact(animated: true)
        }

        // When searchManager returns a map item in mapsStyleMode, show it inline in the sheet.
        mapController.onSearchMapItem = { [weak self] mapItem in
            guard let self else { return }
            self.bottomSheet.showMapItemDetail(mapItem)
            if let sheet = self.bottomSheetNav.sheetPresentationController {
                sheet.animateChanges { sheet.selectedDetentIdentifier = .medium }
            }
        }
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if bottomSheetNav.presentingViewController == nil {
            presentBottomSheet()
        }
    }

    // MARK: - Map embedding

    private func embedMapController() {
        mapController.hideFloatingPanelSearchBar()
        mapController.mapsStyleMode = true

        let mapNav = application.viewRouter.buildNavigation(
            controller: mapController,
            prefersLargeTitles: false
        )
        addChild(mapNav)
        view.addSubview(mapNav.view)
        mapNav.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            mapNav.view.topAnchor.constraint(equalTo: view.topAnchor),
            mapNav.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            mapNav.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            mapNav.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        mapNav.didMove(toParent: self)
        mapController.navigationItem.leftBarButtonItem = nil
        mapController.navigationItem.rightBarButtonItem = nil

        // Reserve space at the bottom so map controls (scale, legal) stay above the sheet.
        mapController.additionalSafeAreaInsets = UIEdgeInsets(
            top: 0, left: 0,
            bottom: Self.compactDetentHeight + 8,  // +8 for the sheet's floating gap above safe area
            right: 0
        )
    }

    // MARK: - Bottom sheet presentation

    private func presentBottomSheet() {
        bottomSheet.delegate = self
        bottomSheetNav.isModalInPresentation = true
        bottomSheetNav.modalPresentationStyle = .pageSheet

        bottomSheet.onSearchBecameActive = { [weak self] in
            guard let self, let sheet = self.bottomSheetNav.sheetPresentationController else { return }
            sheet.animateChanges { sheet.selectedDetentIdentifier = .medium }
        }

        bottomSheet.onDetailShown = { [weak self] in
            guard let self, let sheet = self.bottomSheetNav.sheetPresentationController else { return }
            sheet.animateChanges { sheet.selectedDetentIdentifier = .medium }
        }

        if let sheet = bottomSheetNav.sheetPresentationController {
            configureSheetDetents(sheet)
        }

        present(bottomSheetNav, animated: false)
    }

    private func configureSheetDetents(_ sheet: UISheetPresentationController) {
        let compactDetent = UISheetPresentationController.Detent.custom(
            identifier: Self.compactDetentID
        ) { _ in
            MapsStyleRootController.compactDetentHeight
        }

        sheet.detents = [compactDetent, .medium(), .large()]
        sheet.selectedDetentIdentifier = Self.compactDetentID
        sheet.prefersGrabberVisible = false          // we draw our own grab handle
        sheet.prefersScrollingExpandsWhenScrolledToEdge = true
        sheet.largestUndimmedDetentIdentifier = .medium
        sheet.prefersEdgeAttachedInCompactHeight = true
        sheet.widthFollowsPreferredContentSizeWhenEdgeAttached = true
        sheet.delegate = self
    }

    private func snapSheetToCompact(animated: Bool) {
        guard let sheet = bottomSheetNav.sheetPresentationController else { return }
        sheet.animateChanges {
            sheet.selectedDetentIdentifier = Self.compactDetentID
        }
    }

    // MARK: - Navigation menu (More sheet)

    private func showMoreSheet() {
        let nav = application.viewRouter.buildNavigation(controller: moreController)
        moreController.navigationItem.rightBarButtonItem = UIBarButtonItem(
            systemItem: .close,
            primaryAction: UIAction { [weak nav] _ in nav?.dismiss(animated: true) }
        )
        nav.modalPresentationStyle = .pageSheet
        if let sheetPresentation = nav.sheetPresentationController {
            sheetPresentation.detents = [.medium(), .large()]
            sheetPresentation.prefersGrabberVisible = true
        }
        bottomSheetNav.present(nav, animated: true)
    }

    // MARK: - ApplicationRootController

    public func navigate(to destination: ClassicApplicationRootController.Page) {
        switch destination {
        case .map:
            snapSheetToCompact(animated: true)
        case .recentStops, .bookmarks:
            guard let sheet = bottomSheetNav.sheetPresentationController else { return }
            sheet.animateChanges {
                sheet.selectedDetentIdentifier = .medium
            }
        case .more:
            showMoreSheet()
        }
    }
}

// MARK: - MapBottomSheetDelegate

extension MapsStyleRootController: MapBottomSheetDelegate {
    func mapBottomSheetDidTapRecent(_ sheet: MapBottomSheetViewController) {
        showFullScreenSheet(RecentStopsViewController(application: application))
    }

    func mapBottomSheetDidTapBookmarks(_ sheet: MapBottomSheetViewController) {
        showFullScreenSheet(BookmarksViewController(application: application))
    }

    func mapBottomSheetDidTapMore(_ sheet: MapBottomSheetViewController) {
        showMoreSheet()
    }

    func mapBottomSheet(_ sheet: MapBottomSheetViewController, didSubmitSearch request: SearchRequest) {
        Task { await application.searchManager.search(request: request) }
    }

    func mapBottomSheet(_ sheet: MapBottomSheetViewController, didSelectMapItem mapItem: MKMapItem) {
        // Just center the map — detail is shown inline in the sheet
        let coord = mapItem.placemark.coordinate
        mapController.mapRegionManager.mapView.setCenter(coord, animated: true)
    }

    func mapBottomSheet(_ sheet: MapBottomSheetViewController, didSelectStop stop: Stop) {
        mapController.handleStopSelection(stopID: stop.id)
        snapSheetToCompact(animated: true)
    }

    func mapBottomSheetDidCancelSearch(_ sheet: MapBottomSheetViewController) {
        snapSheetToCompact(animated: true)
    }

    private func showFullScreenSheet(_ vc: UIViewController) {
        let nav = application.viewRouter.buildNavigation(controller: vc)
        vc.navigationItem.rightBarButtonItem = UIBarButtonItem(
            systemItem: .close,
            primaryAction: UIAction { [weak nav] _ in nav?.dismiss(animated: true) }
        )
        nav.modalPresentationStyle = .pageSheet
        if let sheetPresentation = nav.sheetPresentationController {
            sheetPresentation.detents = [.medium(), .large()]
            sheetPresentation.prefersGrabberVisible = true
            sheetPresentation.prefersScrollingExpandsWhenScrolledToEdge = true
        }
        bottomSheetNav.present(nav, animated: true)
    }
}

// MARK: - UINavigationControllerDelegate

extension MapsStyleRootController: UINavigationControllerDelegate {
    public func navigationController(
        _ navigationController: UINavigationController,
        willShow viewController: UIViewController,
        animated: Bool
    ) {
        // Hide nav bar on the root sheet, show it on any pushed VC (gives back button + title)
        let isRoot = viewController === bottomSheet
        navigationController.setNavigationBarHidden(isRoot, animated: animated)

        // Show grab handle only on root
        bottomSheet.setGrabHandleVisible(isRoot)
    }
}

// MARK: - UISheetPresentationControllerDelegate

extension MapsStyleRootController: UISheetPresentationControllerDelegate {
    public func sheetPresentationControllerDidChangeSelectedDetentIdentifier(
        _ sheetPresentationController: UISheetPresentationController
    ) {
        let isExpanded = sheetPresentationController.selectedDetentIdentifier != Self.compactDetentID
        mapController.additionalSafeAreaInsets = UIEdgeInsets(
            top: 0, left: 0,
            bottom: isExpanded ? 0 : Self.compactDetentHeight,
            right: 0
        )

        // When the user drags the sheet up to medium/large without tapping the search bar,
        // enter search mode so the sheet has content (recent searches) instead of being blank.
        if isExpanded && !bottomSheet.isInSearchMode {
            bottomSheet.enterSearchMode(focusTextField: false)
        } else if !isExpanded {
            bottomSheet.exitSearchMode()
        }
    }
}

// MARK: - RegionsServiceDelegate

extension MapsStyleRootController: RegionsServiceDelegate {
    public func regionsService(_ service: RegionsService, updatedRegion region: Region) {
        bottomSheet.updateSearchPlaceholder()
    }
}

// MARK: - ClassicApplicationRootController conformance

extension ClassicApplicationRootController: ApplicationRootController {}
