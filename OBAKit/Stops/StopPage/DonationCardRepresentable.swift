//
//  DonationCardRepresentable.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import OBAKitCore

/// Bridges the existing UIKit `DonationCell` into the SwiftUI Stop page so the
/// inline donation request renders and behaves identically to the legacy screen,
/// reusing the cell rather than reimplementing the donation card.
///
/// All three affordances present VC-owned modals (the learn-more/donate flow and
/// the dismiss action sheet), so their handlers are supplied by the hosting VC and
/// routed through the `StopPageNavigationHandler`.
struct DonationCardRepresentable: UIViewRepresentable {
    /// "Donate Now" and "Learn More" both open the same donation modal, matching
    /// `StopViewController.showDonationUI()`.
    let onDonate: () -> Void
    let onLearnMore: () -> Void
    /// The close (×) button; presents the dismiss action sheet from the VC.
    let onClose: () -> Void

    func makeUIView(context: Context) -> DonationCell {
        let cell = DonationCell(frame: .zero)
        cell.apply(DonationContentConfiguration(makeItem()))
        return cell
    }

    // The donation card's content is static; the closures route to stable VC
    // methods, so there's nothing to reconcile on SwiftUI updates.
    func updateUIView(_ uiView: DonationCell, context: Context) {}

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: DonationCell, context: Context) -> CGSize? {
        let width = proposal.width ?? UIView.layoutFittingCompressedSize.width
        let fitting = uiView.systemLayoutSizeFitting(
            CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        return CGSize(width: width, height: fitting.height)
    }

    private func makeItem() -> DonationListItem {
        DonationListItem(
            onSelectAction: { _ in onDonate() },
            onLearnMoreAction: { _ in onLearnMore() },
            onCloseAction: { _ in onClose() }
        )
    }
}
