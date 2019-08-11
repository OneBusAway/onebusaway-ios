//
//  RouteStopsViewController.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 7/31/19.
//

import UIKit
import MapKit
import Contacts
import AloeStackView
import SafariServices

class RouteStopsViewController: UIViewController, AloeStackTableBuilder, Scrollable {
    /// The OBA application object
    private let application: Application

    lazy var titleView = FloatingPanelTitleView.autolayoutNew()

    lazy var stackView = AloeStackView.autolayoutNew(
        backgroundColor: ThemeColors.shared.groupedTableBackground
    )

    var scrollView: UIScrollView { stackView }

    private let stopsForRoute: StopsForRoute

    public weak var delegate: ModalDelegate?

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

        view.addSubview(stackView)
        stackView.pinToSuperview(.edges)

        titleView.titleLabel.text = stopsForRoute.route.shortName
        titleView.subtitleLabel.text = stopsForRoute.route.longName
        titleView.closeButton.addTarget(self, action: #selector(close), for: .touchUpInside)

        stackView.addRow(titleView)
        stackView.hideSeparator(forRow: titleView)

        addTableHeaderToStack(headerText: NSLocalizedString("route_stops_controller.stops_header", value: "Stops", comment: "A transit vehicle stop."))

        for stop in stopsForRoute.stops {
            let row = SubtitleTableRowView(title: stop.name, subtitle: Formatters.adjectiveFormOfCardinalDirection(stop.direction) ?? "", accessoryType: .disclosureIndicator)
            addGroupedTableRowToStack(row)
            stackView.setTapHandler(forRow: row) { [weak self] _ in
                guard let self = self else { return }
                self.show(stop: stop)
            }
        }
    }

    private func show(stop: Stop) {
        application.viewRouter.navigateTo(stop: stop, from: self)
    }
}
