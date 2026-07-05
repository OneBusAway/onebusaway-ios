//
//  ThemedBulletinPage.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 7/28/20.
//

import UIKit
import OBAKitCore
import BLTNBoard

/// A `BLTNPageItem` subclass that applies the app's brand colors to the buttons and image view.
class ThemedBulletinPage: BLTNPageItem {

    override init(title: String) {
        super.init(title: title)
        customizeAppearance()
    }

    private func customizeAppearance() {
        appearance.actionButtonColor = ThemeColors.shared.brand
        appearance.alternativeButtonTitleColor = ThemeColors.shared.brand
        appearance.imageViewTintColor = ThemeColors.shared.brand
    }
}

extension BLTNItemManager {
    /// Presents the bulletin in the appropriate host for the current experience.
    ///
    /// Map-panel experience (`OBAUseMapPanelExperience` on): the SwiftUI home
    /// sheet's hosting controller is inside a `UISheetPresentationController`
    /// that clamps modal presentations to the current detent — presenting from
    /// there squeezes the bulletin into the collapsed sheet's ~80pt strip. To
    /// dodge the sheet hierarchy, we present into a dedicated `.alert`-level
    /// `UIWindow` via `BulletinOverlayWindow`.
    ///
    /// Classic experience (flag off, production default): fall back to the
    /// pre-#1163 presentation — `keyWindowFromScene?.topViewController`. The
    /// clamping bug doesn't exist there, so the extra window path (and its
    /// singleton lifecycle) is unnecessary.
    ///
    /// Avoid BLTNBoard's built-in `showBulletin(in:)`: it creates a `UIWindow`
    /// without a `windowScene`, which iOS won't display in a scene-based app.
    ///
    /// `rootItem` is the item passed to `BLTNItemManager.init(rootItem:)`; it
    /// has to be supplied here because the manager keeps its reference private,
    /// and the overlay-window path hooks its `dismissalHandler` to retire the
    /// window. It is unused in the classic branch but stays in the signature so
    /// all call sites are identical across experiences.
    @MainActor
    func show(in application: UIApplication, rootItem: BLTNItem) {
        // Re-entrant call while a bulletin is already up: silent no-op is the
        // intended behavior — callers (e.g. reachability flapping) lean on this.
        guard !isShowingBulletin else { return }

        if UserDefaults.standard.bool(forKey: FeatureFlags.useMapPanelExperienceKey) {
            // No usable scene means the bulletin disappears with no UI trace,
            // including for the error path (`Application.displayError`). Log so
            // there's at least a diagnostic breadcrumb instead of silent loss.
            guard let scene = application.bulletinTargetScene else {
                Logger.error("Bulletin dropped: no foreground-active window scene available to host it.")
                return
            }

            let host = BulletinOverlayWindow.shared.install(in: scene, rootItem: rootItem)
            showBulletin(above: host)
        } else {
            // Classic: present above whatever's at the top of the key window.
            // `topViewController` is defined on `UIWindow` in
            // `OBAKitCore/Extensions/UIKitExtensions.swift`.
            guard let topViewController = application.keyWindowFromScene?.topViewController else {
                Logger.error("Bulletin dropped: no key window / top view controller available to host it.")
                return
            }
            showBulletin(above: topViewController)
        }
    }
}

extension UIApplication {
    /// The `UIWindowScene` a bulletin should target.
    ///
    /// Prefers the scene whose key window is actually key — that's where the
    /// user is interacting on multi-window iPad. Filters out external displays
    /// (`.windowExternalDisplayNonInteractive`) so bulletins never land on a
    /// secondary screen no one is touching. Falls back to the first
    /// foreground-active application scene when no key window can be found.
    fileprivate var bulletinTargetScene: UIWindowScene? {
        let activeAppScenes = connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive && $0.session.role == .windowApplication }

        if let interactiveScene = activeAppScenes.first(where: { scene in
            scene.windows.contains(where: \.isKeyWindow)
        }) {
            return interactiveScene
        }
        return activeAppScenes.first
    }
}
