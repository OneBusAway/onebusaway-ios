//
//  FarePayments.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 7/7/19.
//

import UIKit
import StoreKit
import OBAKitCore

// MARK: - Protocol

@objc(OBAFarePaymentsDelegate)
public protocol FarePaymentsDelegate {
    func farePayments(_ farePayments: FarePayments, present viewController: UIViewController, animated: Bool, completion: (() -> Void)?)
    func farePayments(_ farePayments: FarePayments, present error: Error)
}

// MARK: - Fare Payments

/// Manages interoperability with fare payments applications compatible with the current region
@objc(OBAFarePayments)
public class FarePayments: NSObject, SKStoreProductViewControllerDelegate {

    private let application: Application
    private weak var delegate: FarePaymentsDelegate?

    /// Default initializer for this class
    /// - Parameter application: The OBA application object
    /// - Parameter delegate: The object's delegate.
    init(application: Application, delegate: FarePaymentsDelegate) {
        self.application = application
        self.delegate = delegate

        super.init()
    }

    // MARK: - Public

    /// Call this method to either launch the fare payment app, show a confirmation alert, or open the App Store.
    public func beginFarePaymentsWorkflow() {
        guard let region = application.currentRegion else { return }

        application.userDefaults.register(defaults: [
            showWarningDefaultsKey(region): true
        ])

        if region.paymentAppDoesNotCoverFullRegion, application.userDefaults.bool(forKey: showWarningDefaultsKey(region)) {
            displayPaymentAppWarningForRegion(region)
        }
        else {
            launchAppOrShowAppStoreForRegion(region)
        }
    }

    // MARK: - Private Helpers

    /// Calculates the `UserDefaults` key for whether a warning should be displayed for the specified region.
    /// - Parameter region: The region used to calculate the key.
    private func showWarningDefaultsKey(_ region: Region) -> String {
        return "ShowPaymentWarning_Region_\(region.regionIdentifier)"
    }

    /// Shows an alert controller warning the user that the fare payment app for this region does not work across the entire region.
    ///
    /// Depends on the delegate existing to display the `UIAlertController` that is generated.
    /// - Parameter region: The region for which an alert will be displayed.
    private func displayPaymentAppWarningForRegion(_ region: Region) {
        let alert = UIAlertController(title: region.paymentWarningTitle, message: region.paymentWarningBody, preferredStyle: .alert)

        // "Cancel" Button
        alert.addAction(UIAlertAction.cancelAction)

        // "Continue and Don't Show Again" Button
        alert.addAction(title: OBALoc("fare_payments.dont_show_again", value: "Continue and Don't Show Again", comment: "A button that says continue and don't show again.")) { [weak self] _ in
            guard let self = self else { return }
            self.application.userDefaults.set(false, forKey: self.showWarningDefaultsKey(region))
            self.launchAppOrShowAppStoreForRegion(region)
        }

        // "Continue" Button
        alert.addAction(title: Strings.continue) { [weak self] _ in
            guard let self = self else { return }
            self.launchAppOrShowAppStoreForRegion(region)
        }

        delegate?.farePayments(self, present: alert, animated: true, completion: nil)
    }

    /// Launches the fare payment app for the specified region, if it is available. Otherwise, shows the App Store listing.
    /// - Parameter region: The region for which the app or App Store will be displayed.
    private func launchAppOrShowAppStoreForRegion(_ region: Region) {
        guard let deepLinkURL = region.paymentAppDeepLinkURL else { return }

        if application.canOpenURL(deepLinkURL) {
            application.analytics?.reportEvent(.userAction, label: "Clicked Pay Fare Open App", value: nil)
            application.open(deepLinkURL, options: [:], completionHandler: nil)
        }
        else {
            application.analytics?.reportEvent(.userAction, label: "Clicked Pay Fare Download App", value: nil)
            if let identifier = region.paymentiOSAppStoreIdentifier {
                displayAppStorePage(appIdentifier: identifier)
            }
            else {
                // abxoxo - TODO show an error.
            }
        }
    }

    /// Shows the App Store listing for the specified app.
    /// - Parameter appIdentifier: The unique App Store identifier of the app to display.
    private func displayAppStorePage(appIdentifier: String) {
        let storeController = SKStoreProductViewController()
        storeController.delegate = self
        storeController.loadProduct(withParameters: [SKStoreProductParameterITunesItemIdentifier: appIdentifier], completionBlock: nil)
        delegate?.farePayments(self, present: storeController, animated: true, completion: nil)
    }
}
