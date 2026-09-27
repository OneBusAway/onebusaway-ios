//
//  OnDemandDockView.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import OBAKitCore
import SwiftUI

/// The dock slot (spec 2.4): exactly one of nothing, the zone card or the
/// docked bar, cross-fading in 200 ms. Both shells host this one view.
struct OnDemandDockView: View {
    @ObservedObject var controller: OnDemandProbeController
    let actions: OnDemandDockActions
    /// The on-demand layer's drawn colour map (`OnDemandMapLayer.serviceColors`),
    /// so the card and bar match the zones they describe.
    let serviceColors: () -> [String: UIColor]

    private static let crossFade: Double = 0.2

    var body: some View {
        ZStack {
            content
                .id(stateKey)
                .transition(.opacity)
        }
        .animation(.easeInOut(duration: Self.crossFade), value: stateKey)
    }

    /// Changes only when the slot's content changes kind or service set.
    private var stateKey: String {
        switch controller.dockState {
        case .hidden: return "hidden"
        case .card(let matches): return "card-" + matches.map(\.id).joined(separator: ",")
        case .bar(let matches): return "bar-" + matches.map(\.id).joined(separator: ",")
        case .planner(let result): return "planner-" + result.qualifying.map(\.id).joined(separator: ",") + "-\(result.hiddenCount)"
        }
    }

    @ViewBuilder
    private var content: some View {
        switch controller.dockState {
        case .hidden:
            EmptyView()
        case .card(let matches):
            if let check = controller.locationCheck,
               let model = OnDemandZoneCardModel(insideMatches: matches, colors: serviceColors(), copy: copy(for: matches)) {
                OnDemandZoneCardView(model: model, locationCheck: check, actions: Self.perServiceDetailActions(actions, controller: controller))
            }
        case .bar(let matches):
            if let check = controller.locationCheck, let probePoint = controller.probePoint {
                OnDemandDockBarView(
                    model: OnDemandDockBarModel(
                        matches: matches,
                        pickerMatches: OnDemandDockBarModel.pickerCandidates(from: controller.matches),
                        probePoint: probePoint,
                        edges: controller.edgesByServiceID,
                        fullAreas: controller.fullAreasByServiceID,
                        failedGeometry: controller.failedGeometryServiceIDs,
                        colors: serviceColors(),
                        copy: copy(for: matches)
                    ),
                    locationCheck: check,
                    actions: Self.perServiceDetailActions(actions, controller: controller),
                    onPageChange: { controller.highlightedServiceID = $0 }
                )
            }
        case .planner(let result):
            OnDemandPlannerFallbackView(result: result, copy: copy(for: result.qualifying), colors: serviceColors(), actions: actions)
        }
    }

    /// The card and bar pass the probe point's aggregate check; each page
    /// opens its detail with its own service's check instead, so the
    /// location row states that service's inside or nearby fact.
    static func perServiceDetailActions(_ actions: OnDemandDockActions, controller: OnDemandProbeController) -> OnDemandDockActions {
        var perService = actions
        perService.openDetail = { [weak controller] match, aggregate in
            actions.openDetail(match, controller?.locationCheck(forServiceID: match.id) ?? aggregate)
        }
        return perService
    }

    private func copy(for matches: [OnDemandServiceMatch]) -> OnDemandCopy {
        OnDemandCopy(timeZone: matches.first?.service.timeZone ?? .current, now: controller.now())
    }
}
