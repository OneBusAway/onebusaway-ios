//
//  RouteStopsViewController.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import UIKit
import MapKit
import Contacts
import SafariServices
import OBAKitCore

class RouteStopsViewController: VisualEffectViewController,
    AppContext,
    OBAListViewDataSource,
    Scrollable {

    /// The OBA application object
    let application: Application

    weak var delegate: ModalDelegate?
    private let stopsForRoute: StopsForRoute

    private let titleView = FloatingPanelTitleView.autolayoutNew()
    private let listView = OBAListView()
    var scrollView: UIScrollView { listView }

    init(application: Application, stopsForRoute: StopsForRoute, delegate: ModalDelegate?) {
        self.application = application
        self.stopsForRoute = stopsForRoute
        self.delegate = delegate

        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func close() {
        delegate?.dismissModalController(self)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        titleView.titleLabel.text = stopsForRoute.route.shortName
        titleView.subtitleLabel.text = stopsForRoute.route.longName ?? "placeholder for agency name"
//        titleView.subtitleLabel.text = stopsForRoute.route.longName ?? stopsForRoute.route.agency.name
        titleView.closeButton.addTarget(self, action: #selector(close), for: .touchUpInside)

        listView.obaDataSource = self
        listView.showsVerticalScrollIndicator = false
        listView.backgroundColor = nil

        let stack = UIStackView.verticalStack(arrangedSubviews: [titleView, listView])
        visualEffectView.contentView.addSubview(stack)
        stack.pinToSuperview(.edges)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        listView.applyData()
    }

    func items(for listView: OBAListView) -> [OBAListViewSection] {
        let rows = stopsForRoute.stops!.map { stop -> OBAListRowView.SubtitleViewModel in
            let title = stop.name
            let subtitle = Formatters.adjectiveFormOfCardinalDirection(stop.direction) ?? ""
            let stopID = stop.id

            return OBAListRowView.SubtitleViewModel(title: title, subtitle: subtitle, accessoryType: .disclosureIndicator) { _ in
                self.application.viewRouter.navigateTo(stopID: stopID, from: self)
            }
        }

        return [OBAListViewSection(id: "stops", contents: rows)]
    }
}
