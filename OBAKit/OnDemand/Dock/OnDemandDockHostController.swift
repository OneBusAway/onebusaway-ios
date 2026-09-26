//
//  OnDemandDockHostController.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Combine
import SwiftUI
import UIKit

/// Spec 2.4 Regular width and landscape: where the classic shell's dock sits.
enum OnDemandDockPlacement: Equatable {
    /// 16 pt gutters, full width, 12 pt above the sheet.
    case compact
    /// The side panel's width and x-origin, 12 pt above its top edge.
    case sidePanel(width: CGFloat)
    /// The panel is full height: bottom-leading, at most 360 pt wide.
    case floatingLeading(maxWidth: CGFloat)

    static let gutter: CGFloat = 16
    static let gap: CGFloat = 12
    static let floatingMaxWidth: CGFloat = 360

    static func placement(horizontalSizeClass: UIUserInterfaceSizeClass, isPanelFullHeight: Bool) -> OnDemandDockPlacement {
        guard horizontalSizeClass == .regular else { return .compact }
        return isPanelFullHeight ? .floatingLeading(maxWidth: floatingMaxWidth) : .sidePanel(width: MapPanelLandscapeLayout.WidthSize)
    }
}

/// The classic shell's UIKit host for `OnDemandDockView`. Sized by its
/// SwiftUI content; the map controller installs its constraints, which live
/// here with the subscriptions so the map controller stores only the host.
final class OnDemandDockHostController: UIHostingController<OnDemandDockView> {
    /// The placement `placementConstraints` implement; nil before the first layout.
    var placement: OnDemandDockPlacement?
    var placementConstraints: [NSLayoutConstraint] = []
    var cancellables = Set<AnyCancellable>()

    init(controller: OnDemandProbeController, actions: OnDemandDockActions, serviceColors: @escaping () -> [String: UIColor]) {
        super.init(rootView: OnDemandDockView(controller: controller, actions: actions, serviceColors: serviceColors))
        view.backgroundColor = .clear
        view.translatesAutoresizingMaskIntoConstraints = false
        sizingOptions = [.intrinsicContentSize]
        safeAreaRegions = []
    }

    @available(*, unavailable)
    @MainActor required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
