//
//  FixedFloatingPanelView.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import FloatingPanel

/// A fixed version of FloatingPanelView that properly updates the main content
/// when SwiftUI state changes. The original FloatingPanel library has a bug where
/// `updateUIViewController` doesn't update the `rootView` of the hosting controller.
struct FixedFloatingPanelView<MainView: View, ContentView: View>: UIViewControllerRepresentable {
    let coordinator: () -> (any FloatingPanelCoordinator)

    @ViewBuilder
    var main: MainView

    @ViewBuilder
    var content: (FloatingPanelProxy) -> ContentView

    @Environment(\.floatingPanelState)
    private var state: Binding<FloatingPanelState?>

    @Environment(\.floatingPanelLayout)
    private var layout: FloatingPanelLayout

    @Environment(\.floatingPanelBehavior)
    private var behavior: FloatingPanelBehavior

    @Environment(\.floatingPanelContentInsetAdjustmentBehavior)
    private var contentInsetAdjustmentBehavior: FloatingPanelController.ContentInsetAdjustmentBehavior

    @Environment(\.floatingPanelContentMode)
    private var contentMode: FloatingPanelController.ContentMode

    @Environment(\.floatingPanelGrabberHandlePadding)
    private var grabberHandlePadding: CGFloat

    @Environment(\.floatingPanelSurfaceAppearance)
    private var surfaceAppearance: SurfaceAppearance

    func makeCoordinator() -> FixedFloatingPanelCoordinatorProxy<ContentView> {
        return FixedFloatingPanelCoordinatorProxy(
            coordinator: coordinator(),
            state: state,
            content: content
        )
    }

    func makeUIViewController(context: Context) -> UIHostingController<MainView> {
        let mainHostingController = UIHostingController(rootView: main)
        mainHostingController.view.backgroundColor = nil

        let contentHostingController = UIHostingController(rootView: content(context.coordinator.proxy))
        context.coordinator.contentHostingController = contentHostingController

        context.coordinator.setupFloatingPanel(
            mainHostingController: mainHostingController,
            contentHostingController: contentHostingController
        )

        context.coordinator.observeStateChanges()
        context.coordinator.update(layout: layout, behavior: behavior)

        return mainHostingController
    }

    func updateUIViewController(
        _ uiViewController: UIHostingController<MainView>,
        context: Context
    ) {
        // KEY FIX: Update the rootView so that state changes propagate
        uiViewController.rootView = main

        // Also update the content view
        if let contentHostingController = context.coordinator.contentHostingController {
            contentHostingController.rootView = content(context.coordinator.proxy)
        }

        context.coordinator.onUpdate(context: context)
        applyEnvironment(context: context)
        applyAnimatableEnvironment(context: context)
    }

    private func applyEnvironment(context: Context) {
        let fpc = context.coordinator.controller
        if fpc.contentInsetAdjustmentBehavior != contentInsetAdjustmentBehavior {
            fpc.contentInsetAdjustmentBehavior = contentInsetAdjustmentBehavior
        }
        if fpc.contentMode != contentMode {
            fpc.contentMode = contentMode
        }
        if fpc.surfaceView.grabberHandlePadding != grabberHandlePadding {
            fpc.surfaceView.grabberHandlePadding = grabberHandlePadding
        }
        if fpc.surfaceView.appearance != surfaceAppearance {
            fpc.surfaceView.appearance = surfaceAppearance
        }
    }

    private func applyAnimatableEnvironment(context: Context) {
        context.coordinator.apply(
            animatableChanges: {
                context.coordinator.update(state: state.wrappedValue)
                context.coordinator.update(layout: layout, behavior: behavior)
            },
            transaction: context.transaction
        )
    }
}

// MARK: - Coordinator

class FixedFloatingPanelCoordinatorProxy<ContentView: View> {
    private let origin: any FloatingPanelCoordinator
    private var stateBinding: Binding<FloatingPanelState?>
    private let content: (FloatingPanelProxy) -> ContentView

    var proxy: FloatingPanelProxy { origin.proxy }
    var controller: FloatingPanelController { origin.controller }

    // Store reference to content hosting controller for updates
    var contentHostingController: UIHostingController<ContentView>?

    init(
        coordinator: any FloatingPanelCoordinator,
        state: Binding<FloatingPanelState?>,
        content: @escaping (FloatingPanelProxy) -> ContentView
    ) {
        self.origin = coordinator
        self.stateBinding = state
        self.content = content
    }

    func setupFloatingPanel<Main: View>(
        mainHostingController: UIHostingController<Main>,
        contentHostingController: UIHostingController<ContentView>
    ) {
        origin.setupFloatingPanel(
            mainHostingController: mainHostingController,
            contentHostingController: contentHostingController
        )
    }

    func onUpdate<Representable>(
        context: UIViewControllerRepresentableContext<Representable>
    ) where Representable: UIViewControllerRepresentable {
        origin.onUpdate(context: context)
    }

    func update(
        layout: (any FloatingPanelLayout)?,
        behavior: (any FloatingPanelBehavior)?
    ) {
        let shouldInvalidateLayout = controller.layout !== layout

        if let layout = layout {
            controller.layout = layout
        } else {
            controller.layout = FloatingPanelBottomLayout()
        }

        if shouldInvalidateLayout {
            controller.invalidateLayout()
        }

        if let behavior = behavior {
            controller.behavior = behavior
        } else {
            controller.behavior = FloatingPanelDefaultBehavior()
        }
    }

    func update(state: FloatingPanelState?) {
        guard let state = state else { return }
        controller.move(to: state, animated: false)
    }

    func observeStateChanges() {
        // Note: The original FloatingPanel library uses `controller.floatingPanel.statePublisher`
        // but that property is internal. For now, we rely on manual state binding updates.
        // If state synchronization is needed, consider using a FloatingPanelControllerDelegate.
    }

    func apply(animatableChanges: @escaping () -> Void, transaction: Transaction) {
        func animateUsingDefaultAnimator(changes: @escaping () -> Void) {
            let animator = controller.makeDefaultAnimator()
            animator.addAnimations(changes)
            animator.startAnimation()
        }

        if transaction.animation != nil, transaction.disablesAnimations == false {
            animateUsingDefaultAnimator {
                animatableChanges()
            }
        } else {
            animatableChanges()
        }
    }
}

// MARK: - Environment Keys

private struct FloatingPanelStateKey: EnvironmentKey {
    static let defaultValue: Binding<FloatingPanelState?> = .constant(nil)
}

private struct FloatingPanelLayoutKey: EnvironmentKey {
    static let defaultValue: FloatingPanelLayout = FloatingPanelBottomLayout()
}

private struct FloatingPanelBehaviorKey: EnvironmentKey {
    static let defaultValue: FloatingPanelBehavior = FloatingPanelDefaultBehavior()
}

private struct FloatingPanelContentInsetAdjustmentBehaviorKey: EnvironmentKey {
    static let defaultValue: FloatingPanelController.ContentInsetAdjustmentBehavior = .always
}

private struct FloatingPanelContentModeKey: EnvironmentKey {
    static let defaultValue: FloatingPanelController.ContentMode = .static
}

private struct FloatingPanelGrabberHandlePaddingKey: EnvironmentKey {
    static let defaultValue: CGFloat = 6.0
}

private struct FloatingPanelSurfaceAppearanceKey: EnvironmentKey {
    static let defaultValue: SurfaceAppearance = SurfaceAppearance()
}

extension EnvironmentValues {
    var floatingPanelState: Binding<FloatingPanelState?> {
        get { self[FloatingPanelStateKey.self] }
        set { self[FloatingPanelStateKey.self] = newValue }
    }

    var floatingPanelLayout: FloatingPanelLayout {
        get { self[FloatingPanelLayoutKey.self] }
        set { self[FloatingPanelLayoutKey.self] = newValue }
    }

    var floatingPanelBehavior: FloatingPanelBehavior {
        get { self[FloatingPanelBehaviorKey.self] }
        set { self[FloatingPanelBehaviorKey.self] = newValue }
    }

    var floatingPanelContentInsetAdjustmentBehavior: FloatingPanelController.ContentInsetAdjustmentBehavior {
        get { self[FloatingPanelContentInsetAdjustmentBehaviorKey.self] }
        set { self[FloatingPanelContentInsetAdjustmentBehaviorKey.self] = newValue }
    }

    var floatingPanelContentMode: FloatingPanelController.ContentMode {
        get { self[FloatingPanelContentModeKey.self] }
        set { self[FloatingPanelContentModeKey.self] = newValue }
    }

    var floatingPanelGrabberHandlePadding: CGFloat {
        get { self[FloatingPanelGrabberHandlePaddingKey.self] }
        set { self[FloatingPanelGrabberHandlePaddingKey.self] = newValue }
    }

    var floatingPanelSurfaceAppearance: SurfaceAppearance {
        get { self[FloatingPanelSurfaceAppearanceKey.self] }
        set { self[FloatingPanelSurfaceAppearanceKey.self] = newValue }
    }
}

// MARK: - View Extension

extension View {
    /// Overlays this view with a floating panel using the fixed implementation
    /// that properly updates content when SwiftUI state changes.
    func fixedFloatingPanel<T: FloatingPanelCoordinator>(
        coordinator: T.Type = FloatingPanelDefaultCoordinator.self,
        onEvent action: ((T.Event) -> Void)? = nil,
        @ViewBuilder content: @escaping (FloatingPanelProxy) -> some View
    ) -> some View {
        FixedFloatingPanelView(
            coordinator: { T.init(action: action ?? { _ in }) },
            main: { self },
            content: content
        )
        .ignoresSafeArea()
    }

    /// Sets the floating panel state binding (for use with fixedFloatingPanel)
    func fixedFloatingPanelState(_ state: Binding<FloatingPanelState?>) -> some View {
        environment(\.floatingPanelState, state)
    }

    /// Sets the floating panel layout (for use with fixedFloatingPanel)
    func fixedFloatingPanelLayout(_ layout: FloatingPanelLayout) -> some View {
        environment(\.floatingPanelLayout, layout)
    }
}
