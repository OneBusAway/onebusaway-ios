//
//  RentalLinkOpener.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import OBAKitCore
import StoreKit
import UIKit

/// Opens a rental sheet's "Open in <operator>" target, and decides where the
/// rider lands when that fails. The one implementation behind both map surfaces:
/// the UIKit map and the map panel used to carry their own copies, and the panel's
/// had already lost its analytics.
///
/// No `canOpenURL` pre-check, deliberately: Apple's guidance is to attempt the
/// open and handle failure, and `open` — unlike `canOpenURL` — is not constrained
/// by `LSApplicationQueriesSchemes`. Failure is routine, not exceptional: the
/// Lime link is synthesized from an undocumented scheme (see `RentalDeepLink`),
/// and most riders tapping it will not have Lime installed.
///
/// The order of fallbacks:
/// 1. https links open with `.universalLinksOnly`, so an installed operator app
///    claims them and an absent one reports failure rather than opening Safari.
/// 2. With a known App Store id, the operator's App Store page is presented
///    in-app (`SKStoreProductViewController`), so the rider can install and come
///    straight back to the vehicle they picked. If the page cannot load, the
///    https App Store URL opens instead.
/// 3. Otherwise an https link opens normally, in Safari; any other link falls
///    back to `Target.storeFallback`.
@MainActor final class RentalLinkOpener {

    typealias OpenURL = (URL, [UIApplication.OpenExternalURLOptionsKey: Any], @escaping (Bool) -> Void) -> Void

    /// Analytics: an `AnalyticsLabels` label and the network id.
    typealias Report = (_ label: String, _ networkID: String?) -> Void

    /// Presents the App Store page for an id; calls back with whether it loaded.
    typealias PresentStore = (_ appStoreID: String, _ completion: @escaping (Bool) -> Void) -> Void

    private let openURL: OpenURL
    private let report: Report
    private let presentStore: PresentStore

    init(open: @escaping OpenURL, report: @escaping Report, presentStore: @escaping PresentStore) {
        self.openURL = open
        self.report = report
        self.presentStore = presentStore
    }

    func open(_ target: RentalDeepLink.Target, networkID: String?) {
        report(AnalyticsLabels.rentalDeepLinkTapped, networkID)

        let url = target.url
        let isWebLink = Self.isWebURL(url)
        let options: [UIApplication.OpenExternalURLOptionsKey: Any] = isWebLink ? [.universalLinksOnly: true] : [:]

        // Strong captures throughout: callers build an opener per tap and drop it,
        // so these completions are what keep it alive until the fallback has run.
        openURL(url, options) { success in
            guard !success else { return }
            Logger.info("Rental deep link did not open an app: \(url)")
            self.report(AnalyticsLabels.rentalDeepLinkFallbackFired, networkID)
            self.fallBack(from: target, isWebLink: isWebLink)
        }
    }

    private func fallBack(from target: RentalDeepLink.Target, isWebLink: Bool) {
        if let appStoreID = target.appStoreID {
            presentStore(appStoreID) { loaded in
                guard !loaded, let storeURL = RentalDeepLink.appStoreURL(forID: appStoreID) else { return }
                self.openURL(storeURL, [:]) { _ in }
            }
            return
        }

        if isWebLink {
            openURL(target.url, [:]) { _ in }
        } else if let storeFallback = target.storeFallback {
            openURL(storeFallback, [:]) { _ in }
        }
    }

    private static func isWebURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "https" || scheme == "http"
    }
}

// MARK: - Live wiring

extension RentalLinkOpener {

    /// The production opener: `Application.open`, its analytics, and an in-app
    /// store sheet presented over whatever `presenter` returns.
    ///
    /// `presenter` is resolved at failure time, not at construction: the sheet the
    /// rider tapped in is a modal, and the store page must go over it — UIKit
    /// silently refuses a `present` on a controller that is already presenting.
    static func live(application: Application, presenter: @escaping () -> UIViewController?) -> RentalLinkOpener {
        RentalLinkOpener(
            open: { [weak application] url, options, completion in
                guard let application else { return completion(false) }
                application.open(url, options: options, completionHandler: completion)
            },
            report: { [weak application] label, networkID in
                application?.analytics?.reportEvent(pageURL: "app://localhost/bikeshare", label: label, value: networkID)
            },
            presentStore: { appStoreID, completion in
                guard let presenter = presenter()?.topmostPresentedController else { return completion(false) }
                StoreProductPresenter.present(appStoreID: appStoreID, from: presenter, completion: completion)
            }
        )
    }
}

/// Loads an App Store product page, then presents it. Loading first means a page
/// that cannot load (no network, a stale id, the Simulator) never flashes an
/// empty sheet; the caller falls back to the web App Store instead.
@MainActor private enum StoreProductPresenter {

    /// `SKStoreProductViewController` leaves dismissal to its delegate, and holds
    /// that delegate weakly — so it must outlive any one presentation.
    private final class Dismisser: NSObject, SKStoreProductViewControllerDelegate {
        func productViewControllerDidFinish(_ viewController: SKStoreProductViewController) {
            viewController.presentingViewController?.dismiss(animated: true)
        }
    }

    private static let dismisser = Dismisser()

    static func present(appStoreID: String, from presenter: UIViewController, completion: @escaping (Bool) -> Void) {
        let store = SKStoreProductViewController()
        store.delegate = dismisser

        Task { @MainActor [weak presenter] in
            do {
                try await store.loadProduct(withParameters: [SKStoreProductParameterITunesItemIdentifier: appStoreID])
            } catch {
                Logger.info("App Store page \(appStoreID) failed to load: \(error)")
                completion(false)
                return
            }
            guard let presenter, presenter.presentedViewController == nil else {
                completion(false)
                return
            }
            presenter.present(store, animated: true)
            completion(true)
        }
    }
}
