//
//  MapItemViewController.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import UIKit
import SwiftUI
import MapKit
import OBAKitCore

/// A view controller that displays information about a map item (location/place) in a modal presentation.
///
/// This view controller acts as a UIKit wrapper around a SwiftUI view (`MapItemView`), using `UIHostingController`
/// to bridge between the two frameworks. It displays location details such as address, phone number, and website,
/// and provides a link to view nearby transit stops.
///
class MapItemViewController: UIViewController, AppContext {
    let application: Application

    private let mapItem: MKMapItem
    private weak var modalDelegate: ModalDelegate?
    private let removePinHandler: (() -> Void)?
    private let planTripHandler: () -> Void

    /// The hosting controller that embeds the SwiftUI view
    private var hostingController: UIHostingController<AnyView>?

    /// The view model, built in `viewDidLoad` because `MapItemActions.uiKit` needs
    /// this controller as its presenter — which isn't available until after
    /// `super.init`.
    private var viewModel: MapItemViewModel?

    init(
        application: Application,
        mapItem: MKMapItem,
        delegate: ModalDelegate?,
        removePinHandler: (() -> Void)? = nil,
        planTripHandler: @escaping () -> Void
    ) {
        self.application = application
        self.mapItem = mapItem
        self.modalDelegate = delegate
        self.removePinHandler = removePinHandler
        self.planTripHandler = planTripHandler
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()

        let viewModel = MapItemViewModel(
            mapItem: mapItem,
            application: application,
            actions: .uiKit(presenter: self, delegate: modalDelegate, application: application),
            removePinHandler: removePinHandler,
            planTripHandler: planTripHandler
        )
        self.viewModel = viewModel

        view.backgroundColor = .clear

        // The blurred surface used to live inside `MapItemView`. It's panel chrome,
        // not content — and inside a SwiftUI sheet it fights the sheet's own
        // material — so the UIKit host owns it now.
        let background = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
        view.addSubview(background)
        background.pinToSuperview(.edges)

        let mapItemView = MapItemView(viewModel: viewModel, showsShareButton: true)
            .environment(\.coreApplication, application)

        let hostingController = UIHostingController(rootView: AnyView(mapItemView))
        hostingController.view.backgroundColor = .clear

        addChild(hostingController)
        view.addSubview(hostingController.view)
        hostingController.view.pinToSuperview(.edges)
        hostingController.didMove(toParent: self)

        self.hostingController = hostingController
    }
}
