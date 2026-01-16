//
//  MapPanelCoordinator.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 11/27/25.
//

import UIKit
import FloatingPanel
import SwiftUI

final class MapPanelCoordinator: FloatingPanelCoordinator {
    enum Event {}

    let action: (Event) -> Void
    let proxy: FloatingPanelProxy

    private lazy var delegate: FloatingPanelControllerDelegate? = self

    init(action: @escaping (Event) -> Void) {
        self.action = action
        self.proxy = .init(controller: FloatingPanelController())
    }

    public func setupFloatingPanel<Main: View, Content: View>(
        mainHostingController: UIHostingController<Main>,
        contentHostingController: UIHostingController<Content>
    ) {
        // Put me back if we experience issues with the keyboard.
//        mainHostingController.ignoresKeyboardSafeArea()
//        contentHostingController.ignoresKeyboardSafeArea()

        // Set the delegate object
        controller.delegate = delegate

        // Set up the content
        contentHostingController.view.backgroundColor = nil
        controller.set(contentViewController: contentHostingController)

        // Show the panel
        controller.addPanel(toParent: mainHostingController, animated: false)
    }

    func onUpdate<Representable>(
        context: UIViewControllerRepresentableContext<Representable>
    ) where Representable: UIViewControllerRepresentable {}
}

extension MapPanelCoordinator: FloatingPanelControllerDelegate {
    func floatingPanelWillBeginAttracting(
        _ fpc: FloatingPanelController,
        to state: FloatingPanelState
    ) {
        if fpc.state == .full {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
    }
}
