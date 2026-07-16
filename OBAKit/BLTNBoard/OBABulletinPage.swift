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

    // nonisolated to match BLTNPageItem's nonisolated designated initializer; only
    // touches BLTNBoard state and the Sendable ThemeColors.
    //
    // Subclasses that declare their own designated initializer must also
    // re-declare this one as `@available(*, unavailable) nonisolated override`:
    // the implicitly-synthesized override would otherwise get main-actor
    // isolation and mismatch this nonisolated declaration.
    nonisolated override init(title: String) {
        super.init(title: title)
        customizeAppearance()
    }

    nonisolated private func customizeAppearance() {
        appearance.actionButtonColor = ThemeColors.shared.brand
        appearance.alternativeButtonTitleColor = ThemeColors.shared.brand
        appearance.imageViewTintColor = ThemeColors.shared.brand
    }
}

extension BLTNItemManager {
    /// Presents the bulletin in a dedicated overlay `UIWindow` attached to the
    /// active scene.
    ///
    /// Avoid `showBulletin(in:)` (BLTNBoard's built-in): it creates a `UIWindow`
    /// without a `windowScene`, which iOS won't display in a scene-based app.
    /// Avoid presenting from `keyWindowFromScene?.topViewController` directly:
    /// in the SwiftUI map-panel experience that walk lands inside the home
    /// sheet's hosting controller, and `UISheetPresentationController` clamps
    /// modal presentations to the sheet's current detent — the bulletin then
    /// renders inside the collapsed sheet's ~80pt strip.
    ///
    /// `rootItem` is the item passed to `BLTNItemManager.init(rootItem:)`; it
    /// has to be supplied here because the manager keeps its reference private,
    /// and we hook its `dismissalHandler` to retire the overlay window.
    @MainActor
    func show(in application: UIApplication, rootItem: BLTNItem) {
        // Re-entrant call while a bulletin is already up: silent no-op is the
        // intended behavior — callers (e.g. reachability flapping) lean on this.
        guard !isShowingBulletin else { return }

        // No usable scene means the bulletin disappears with no UI trace,
        // including for the error path (`Application.displayError`). Log so
        // there's at least a diagnostic breadcrumb instead of silent loss.
        guard let scene = application.bulletinTargetScene else {
            Logger.error("Bulletin dropped: no foreground-active window scene available to host it.")
            return
        }

        let host = BulletinOverlayWindow.shared.install(in: scene, rootItem: rootItem)
        showBulletin(above: host)
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
