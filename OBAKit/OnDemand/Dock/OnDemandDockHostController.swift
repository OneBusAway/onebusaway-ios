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
    /// The panel is full height: bottom-leading over the visible map, just
    /// right of the panel, at most 360 pt wide.
    case floatingLeading(maxWidth: CGFloat)

    static let gutter: CGFloat = 16
    static let gap: CGFloat = 12
    static let floatingMaxWidth: CGFloat = 360

    static func placement(horizontalSizeClass: UIUserInterfaceSizeClass, isPanelFullHeight: Bool) -> OnDemandDockPlacement {
        guard horizontalSizeClass == .regular else { return .compact }
        return isPanelFullHeight ? .floatingLeading(maxWidth: floatingMaxWidth) : .sidePanel(width: MapPanelLandscapeLayout.WidthSize)
    }

    /// Pins `dockView` horizontally and vertically; its height comes from
    /// `OnDemandDockHostController`. `surface` is the floating panel's surface.
    func constraints(dockView: UIView, safeArea: UILayoutGuide, surface: UIView) -> [NSLayoutConstraint] {
        switch self {
        case .compact:
            return [
                dockView.leadingAnchor.constraint(equalTo: safeArea.leadingAnchor, constant: Self.gutter),
                dockView.trailingAnchor.constraint(equalTo: safeArea.trailingAnchor, constant: -Self.gutter),
                dockView.bottomAnchor.constraint(equalTo: surface.topAnchor, constant: -Self.gap)
            ]
        case .sidePanel(let width):
            return [
                dockView.leadingAnchor.constraint(equalTo: surface.leadingAnchor),
                dockView.widthAnchor.constraint(equalToConstant: width),
                dockView.bottomAnchor.constraint(equalTo: surface.topAnchor, constant: -Self.gap)
            ]
        case .floatingLeading(let maxWidth):
            // The full-height panel covers the leading edge, so the dock
            // starts past it; it takes the full width unless the map is narrower.
            let preferredWidth = dockView.widthAnchor.constraint(equalToConstant: maxWidth)
            preferredWidth.priority = .defaultHigh
            return [
                dockView.leadingAnchor.constraint(equalTo: surface.trailingAnchor, constant: Self.gutter),
                preferredWidth,
                dockView.widthAnchor.constraint(lessThanOrEqualToConstant: maxWidth),
                dockView.trailingAnchor.constraint(lessThanOrEqualTo: safeArea.trailingAnchor, constant: -Self.gutter),
                dockView.bottomAnchor.constraint(equalTo: safeArea.bottomAnchor, constant: -Self.gutter)
            ]
        }
    }
}

/// The classic shell's UIKit host for `OnDemandDockView`. The placement
/// fixes its width; its height is the SwiftUI content's height at that
/// width, so a wrapping title grows the dock instead of clipping. The
/// constraints and subscriptions live here so the map controller stores
/// only the host.
final class OnDemandDockHostController: UIHostingController<OnDemandDockView> {
    /// The placement `placementConstraints` implement; nil before the first layout.
    var placement: OnDemandDockPlacement?
    var placementConstraints: [NSLayoutConstraint] = []
    var cancellables = Set<AnyCancellable>()

    private lazy var heightConstraint = view.heightAnchor.constraint(equalToConstant: 0)

    init(controller: OnDemandProbeController, actions: OnDemandDockActions, serviceColors: @escaping () -> [String: UIColor]) {
        super.init(rootView: OnDemandDockView(controller: controller, actions: actions, serviceColors: serviceColors))
        view.backgroundColor = .clear
        view.translatesAutoresizingMaskIntoConstraints = false
        safeAreaRegions = []
        heightConstraint.isActive = true

        // `objectWillChange` fires before the new state lands; measure after.
        controller.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateHeight() }
            .store(in: &cancellables)
    }

    @available(*, unavailable)
    @MainActor required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateHeight()
    }

    /// The content's height when laid out at `width`.
    func fittingHeight(forWidth width: CGFloat) -> CGFloat {
        guard width > 0 else { return 0 }
        return sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude)).height
    }

    /// Re-measures at the current width; a no-op when the height is unchanged,
    /// so the layout pass this triggers settles.
    func updateHeight() {
        let height = fittingHeight(forWidth: view.bounds.width)
        guard height != heightConstraint.constant else { return }
        heightConstraint.constant = height
    }
}
