//
//  StopSheetViewController.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import UIKit
import MapKit
import OBAKitCore

// MARK: - StopSheetDelegate

protocol StopSheetDelegate: AnyObject {
    func stopSheetDidDismiss(_ sheet: StopSheetViewController)
    func stopSheetDidExpand(_ sheet: StopSheetViewController)
    func stopSheetDidCollapse(_ sheet: StopSheetViewController)
}

extension StopSheetDelegate {
    func stopSheetDidExpand(_ sheet: StopSheetViewController) {}
    func stopSheetDidCollapse(_ sheet: StopSheetViewController) {}
}

// MARK: - StopSheetViewController

/// Presents a `StopViewController` as a native iOS sheet with two detents:
/// - **Half** (~50%) — stop header + first departures, map visible above.
/// - **Large** — full stop detail with close button top-left.
final class StopSheetViewController: UINavigationController {

    // MARK: - Properties

    weak var stopSheetDelegate: StopSheetDelegate?
    private let stop: Stop?

    // MARK: - Custom detent

    static let halfDetentID = UISheetPresentationController.Detent.Identifier("stopHalf")

    private static var halfDetent: UISheetPresentationController.Detent {
        .custom(identifier: halfDetentID) { context in
            context.maximumDetentValue * 0.50
        }
    }

    // MARK: - Init

    init(application: Application, stop: Stop, bookmark: Bookmark? = nil, transferContext: TransferContext? = nil) {
        self.stop = stop
        let stopVC = StopViewController(application: application, stop: stop)
        stopVC.bookmarkContext = bookmark
        stopVC.transferContext = transferContext
        super.init(rootViewController: stopVC)
        configureSheet()
        configureNavBar()
    }

    init(application: Application, stopID: StopID) {
        self.stop = nil
        let stopVC = StopViewController(application: application, stopID: stopID)
        super.init(rootViewController: stopVC)
        configureSheet()
        configureNavBar()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - Sheet configuration

    private func configureSheet() {
        modalPresentationStyle = .pageSheet
        guard let sheet = sheetPresentationController else { return }
        sheet.detents = [Self.halfDetent, .large()]
        sheet.selectedDetentIdentifier = Self.halfDetentID
        sheet.largestUndimmedDetentIdentifier = Self.halfDetentID
        sheet.prefersGrabberVisible = true
        sheet.prefersScrollingExpandsWhenScrolledToEdge = true
        sheet.preferredCornerRadius = 20
        sheet.delegate = self
        // Set ourselves as nav delegate so we can re-assert the close button
        // whenever a view controller is about to be shown
        self.delegate = self
    }

    private func configureNavBar() {
        // Keep nav bar visible so StopViewController's right bar buttons (schedule, filter, more) remain.
        let appearance = UINavigationBarAppearance()
        appearance.configureWithDefaultBackground()
        appearance.backgroundEffect = UIBlurEffect(style: .systemMaterial)
        appearance.shadowColor = .clear
        navigationBar.standardAppearance = appearance
        navigationBar.scrollEdgeAppearance = appearance
        navigationBar.compactAppearance = appearance
        navigationBar.isTranslucent = true
    }

    // MARK: - Close button

    private lazy var closeBarButton: UIBarButtonItem = {
        let config = UIImage.SymbolConfiguration(pointSize: 22, weight: .regular)
        let img = UIImage(systemName: "xmark.circle.fill", withConfiguration: config)?
            .withRenderingMode(.alwaysTemplate)
        let btn = UIBarButtonItem(image: img, style: .plain, target: self, action: #selector(closeTapped))
        btn.tintColor = .tertiaryLabel
        btn.accessibilityLabel = "Close"
        return btn
    }()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        installCloseButton()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        installCloseButton()
    }

    private func installCloseButton() {
        guard let stopVC = topViewController else { return }
        // Only set if not already ours — avoids redundant layout passes
        if stopVC.navigationItem.leftBarButtonItem !== closeBarButton {
            stopVC.navigationItem.leftBarButtonItem = closeBarButton
            stopVC.navigationItem.hidesBackButton = true
        }
    }

    // MARK: - Close action

    @objc private func closeTapped() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        // Fire delegate manually — presentationControllerDidDismiss only fires on swipe dismiss
        stopSheetDelegate?.stopSheetDidDismiss(self)
        dismiss(animated: true)
    }

    // MARK: - Presentation

    func present(from fromController: UIViewController, centeringMap mapView: MKMapView? = nil) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        fromController.present(self, animated: true) { [weak self] in
            guard let self, let stop = self.stop, let mapView else { return }
            self.centerMap(mapView, on: stop.coordinate)
        }
    }

    // MARK: - Map centering

    private func centerMap(_ mapView: MKMapView, on coordinate: CLLocationCoordinate2D) {
        let offsetFraction = 0.25
        var region = mapView.region
        region.center = CLLocationCoordinate2D(
            latitude: coordinate.latitude - (region.span.latitudeDelta * offsetFraction),
            longitude: coordinate.longitude
        )
        UIView.animate(
            withDuration: 0.4, delay: 0,
            usingSpringWithDamping: 0.85, initialSpringVelocity: 0.5,
            options: .curveEaseOut
        ) {
            mapView.setRegion(region, animated: false)
        }
    }

    func restoreMapCenter(_ mapView: MKMapView, to coordinate: CLLocationCoordinate2D) {
        var region = mapView.region
        region.center = coordinate
        UIView.animate(withDuration: 0.35, delay: 0, options: .curveEaseOut) {
            mapView.setRegion(region, animated: false)
        }
    }
}

// MARK: - UINavigationControllerDelegate

extension StopSheetViewController: UINavigationControllerDelegate {
    func navigationController(
        _ navigationController: UINavigationController,
        willShow viewController: UIViewController,
        animated: Bool
    ) {
        installCloseButton()
    }
}

// MARK: - UISheetPresentationControllerDelegate

extension StopSheetViewController: UISheetPresentationControllerDelegate {

    func sheetPresentationControllerDidChangeSelectedDetentIdentifier(
        _ controller: UISheetPresentationController
    ) {
        if controller.selectedDetentIdentifier == .large {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            stopSheetDelegate?.stopSheetDidExpand(self)
        } else {
            stopSheetDelegate?.stopSheetDidCollapse(self)
        }
    }

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        UISelectionFeedbackGenerator().selectionChanged()
        stopSheetDelegate?.stopSheetDidDismiss(self)
    }

    func adaptivePresentationStyle(
        for controller: UIPresentationController,
        traitCollection: UITraitCollection
    ) -> UIModalPresentationStyle {
        return .pageSheet
    }
}
