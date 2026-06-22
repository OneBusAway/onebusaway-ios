//
//  FloatingSheetContainer.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI

// MARK: - FloatingSheetContainer

/// A `ViewModifier` that presents a persistent, never-dismissed bottom sheet
/// and hosts an optional stacked sheet on top.
///
/// Hosting the stacked sheet here (rather than on any one content view) keeps
/// it alive across base-sheet push/pop — its lifetime is the whole sheet system,
/// not any single route.
struct FloatingSheetContainer<Route: SheetRouteable, SheetContent: View>: ViewModifier {
    @ObservedObject var coordinator: SheetCoordinator<Route>
    let sheetContent: (Route) -> SheetContent

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: .constant(true)) {
                sheetContent(coordinator.currentRoute)
                    .applyDetentConfig(
                        coordinator.currentRoute.detentConfiguration,
                        selection: $coordinator.currentDetent,
                        interactiveDismissDisabled: coordinator.currentRoute.detentConfiguration.isDismissDisabled
                    )
                    .environmentObject(coordinator)
                    .modifier(
                        StackedSheetLayer(
                            coordinator: coordinator,
                            depth: 0,
                            sheetContent: sheetContent
                        )
                    )
            }
    }
}

// MARK: - StackedSheetLayer

/// Recursive layer of the stacked-sheet pile. Layer `depth` attaches a
/// `.sheet(item:)` whose `item` is `coordinator.stackedRoutes[depth]`. When
/// presented, that sheet's content carries the next layer (`depth + 1`) — so
/// each stacked route gets its own physical `UISheetPresentationController`
/// with the previous sheet peeking beneath.
///
/// Implemented as a `ViewModifier` (not a `View`) so the `.sheet` modifier attaches directly to the host content
private struct StackedSheetLayer<Route: SheetRouteable, SheetContent: View>: ViewModifier {
    @ObservedObject var coordinator: SheetCoordinator<Route>
    let depth: Int
    let sheetContent: (Route) -> SheetContent

    private var routeBinding: Binding<Route?> {
        Binding(
            get: { coordinator.stackedRoutes.indices.contains(depth) ? coordinator.stackedRoutes[depth] : nil },
            set: { newValue in
                if newValue == nil {
                    coordinator.truncateStacked(toDepth: depth)
                }
            }
        )
    }

    private func detentBinding(for route: Route) -> Binding<PresentationDetent> {
        Binding(
            get: {
                coordinator.stackedEntries.indices.contains(depth)
                    ? coordinator.stackedEntries[depth].detent
                    : route.detentConfiguration.initialDetent
            },
            set: { newValue in
                coordinator.setStackedDetent(newValue, at: depth)
            }
        )
    }

    func body(content: Content) -> some View {
        content.sheet(item: routeBinding) { route in
            sheetContent(route)
                .applyDetentConfig(
                    route.detentConfiguration,
                    selection: detentBinding(for: route),
                    interactiveDismissDisabled: route.detentConfiguration.isDismissDisabled
                )
                .environmentObject(coordinator)
                .modifier(StackedSheetLayer(
                    coordinator: coordinator,
                    depth: depth + 1,
                    sheetContent: sheetContent
                ))
        }
    }
}

// MARK: - Detent configuration helper

private extension View {
    func applyDetentConfig(
        _ config: SheetDetentConfiguration,
        selection: Binding<PresentationDetent>,
        interactiveDismissDisabled: Bool
    ) -> some View {
        // When parked at `fullScreenDetent` (sheet covers the screen — common on iPhone landscape with the full-coverage detent),
        // background interaction is forced off since nothing remains behind to touch.
        let effectiveBackgroundInteraction: PresentationBackgroundInteraction = {
            if let fullScreen = config.fullScreenDetent, selection.wrappedValue == fullScreen {
                return .disabled
            }
            return config.backgroundInteraction
        }()

        return self
            .presentationDetents(config.detents, selection: selection)
            .presentationDragIndicator(config.showDragIndicator ? .visible : .hidden)
            .interactiveDismissDisabled(interactiveDismissDisabled)
            .presentationBackgroundInteraction(config.backgroundInteraction)
            // On iPad / regular size class, force the sheet shape instead of
            // adapting to a popover — the map panel is map-first, and a
            // popover wouldn't preserve the floating-over-the-map model.
            .presentationCompactAdaptation(.none)
            .legacyFloatingCornerRadius()
    }
}

// MARK: - Legacy corner radius

private extension View {
    /// On iOS 26+, sheets render as floating rounded cards natively. On older
    /// systems they're flush with the screen and corner radius is more conservative,
    /// so we bump it up to approximate the iOS 26 look (especially noticeable on
    /// small detents like `.height(80)` where the default radius reads as square).
    @ViewBuilder
    func legacyFloatingCornerRadius() -> some View {
        if #available(iOS 26.0, *) {
            self
        } else {
            self.presentationCornerRadius(24)
        }
    }
}

// MARK: - View Extension

extension View {
    /// Attaches a persistent floating sheet driven by `coordinator`.
    func floatingSheet<Route: SheetRouteable, Content: View>(
        coordinator: SheetCoordinator<Route>,
        @ViewBuilder content: @escaping (Route) -> Content
    ) -> some View {
        modifier(FloatingSheetContainer(coordinator: coordinator, sheetContent: content))
    }
}
