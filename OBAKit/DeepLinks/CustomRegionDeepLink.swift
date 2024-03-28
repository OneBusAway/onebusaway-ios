//
//  CustomRegionDeepLink.swift
//  OBAKit
//
//  Created by Hilmy Veradin on 27/03/24.
//

import Foundation
import UIKit
import OBAKitCore
import SwiftUI
import MapKit

@objc public class CustomRegionDeepLink: NSObject {

    @objc(parseURL:application:) public static func parseURL(_ url: URL, application: Application) {
        // Check if the add-region URL is null then return the default URL
        guard url.host == "add-region" else {
            return
        }

        // Proceed with parsing the URL
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: true),
              let queryItems = components.queryItems,
              let name = queryItems.first(where: { $0.name == "name" })?.value,
              let obaUrlString = queryItems.first(where: { $0.name == "oba-url" })?.value,
              let obaUrl = URL(string: obaUrlString) else {

            // Show an error message when the custom URL is invalid
            displayErrorMessage(application: application)
            return
        }

        guard let apiService = application.apiService else {
            return
        }

        Task { @MainActor in
            do {
                application.viewRouter.rootNavigateTo(page: .map)

                guard var regionCoordinate = try await apiService.getAgenciesWithCoverage().list.first?.region ?? nil else { return  }

                // Manually set the span of latitude and longitude delta because the value of latitude and longitude region is very small
                regionCoordinate.span.latitudeDelta = 2
                regionCoordinate.span.longitudeDelta = 2

                // Attempt to extract otp-url if present
                let otpUrlString = queryItems.first(where: { $0.name == "otp-url" })?.value
                let otpUrl = otpUrlString != nil ? URL(string: otpUrlString!) : nil

                // Create region provider
                let regionProvider = RegionPickerCoordinator(regionsService: application.regionsService)

                // Set current region based on given URL
                let currentRegion = Region(name: name, OBABaseURL: obaUrl, coordinateRegion: regionCoordinate, contactEmail: "example@example.com", openTripPlannerURL: otpUrl)

                // Add and set current region
                try await regionProvider.add(customRegion: currentRegion)
                try await regionProvider.setCurrentRegion(to: currentRegion)
            }
        }

    }

    static func displayErrorMessage(application: Application) {
        DispatchQueue.main.async {
            // Obtain the current window and key window
            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
            guard let keyWindow = windowScene.windows.first(where: { $0.isKeyWindow }) else { return }

            let alertController = UIAlertController(
                title: "Error",
                message: "The provided region URL is invalid or does not point to a functional OBA server.",
                preferredStyle: .alert
            )
            alertController.addAction(UIAlertAction(title: "OK", style: .default))

            // Get the root view controller of the key window and present the alert controller
            if let rootViewController = keyWindow.rootViewController {
                presentOnTopViewController(rootViewController: rootViewController, viewControllerToPresent: alertController)
            }
        }
    }

    // Ensure presentOnTopViewController is updated to work with the current setup
    static func presentOnTopViewController(rootViewController: UIViewController, viewControllerToPresent: UIViewController) {
        var currentViewController = rootViewController
        while let presentedViewController = currentViewController.presentedViewController {
            currentViewController = presentedViewController
        }
        currentViewController.present(viewControllerToPresent, animated: true, completion: nil)
    }

}
