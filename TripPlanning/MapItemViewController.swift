//
//  MapItemViewController.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 7/29/19.
//

import UIKit
import MapKit
import Contacts
import AloeStackView
import SafariServices
import OBAKitCore

class MapItemViewController: UIViewController, AloeStackTableBuilder, Scrollable {
    /// The OBA application object
    private let application: Application

    lazy var titleView = FloatingPanelTitleView.autolayoutNew()

    lazy var stackView = AloeStackView.autolayoutNew(
        backgroundColor: ThemeColors.shared.groupedTableBackground
    )

    var scrollView: UIScrollView { stackView }

    private let mapItem: MKMapItem

    public weak var delegate: ModalDelegate?

    init(application: Application, mapItem: MKMapItem, delegate: ModalDelegate?) {
        self.application = application
        self.mapItem = mapItem
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

        titleView.titleLabel.text = mapItem.name ?? ""
        titleView.closeButton.addTarget(self, action: #selector(close), for: .touchUpInside)

        stackView.addRow(titleView)
        stackView.hideSeparator(forRow: titleView)

        addGroupedTableHeaderToStack(headerText: NSLocalizedString("map_item_controller.about_header", value: "About", comment: "about section header"))

        if let address = mapItem.placemark.postalAddress {
            let formattedAddress = CNPostalAddressFormatter.string(from: address, style: .mailingAddress)
            addGroupedTableRowToStack(DefaultTableRowView(title: formattedAddress, accessoryType: .none), isLastRow: false) { [weak self]_ in
                guard let self = self else { return }

                self.mapItem.openInMaps(launchOptions: nil)
            }
        }

        if let phone = mapItem.phoneNumber, let url = URL(phoneNumber: phone) {
            addGroupedTableRowToStack(DefaultTableRowView(title: phone, accessoryType: .none), isLastRow: false) { [weak self] _ in
                guard let self = self else { return }
                self.application.open(url, options: [:], completionHandler: nil)
            }
        }

        if let url = mapItem.url {
            addGroupedTableRowToStack(DefaultTableRowView(title: url.absoluteString, accessoryType: .none), isLastRow: false) { [weak self] _ in
                guard let self = self else { return }

                let safari = SFSafariViewController(url: url)
                self.application.viewRouter.present(safari, from: self)
            }
        }

        addGroupedTableHeaderToStack(headerText: NSLocalizedString("map_item_controller.more_header", value: "More", comment: "More options header"))
        addGroupedTableRowToStack(DefaultTableRowView(title: NSLocalizedString("map_item_controller.nearby_stops_row", value: "Nearby Stops", comment: "A table row that shows stops nearby."), accessoryType: .disclosureIndicator), isLastRow: false) { [weak self] _ in
            guard let self = self else { return }

            let nearbyStops = NearbyStopsViewController(coordinate: self.mapItem.placemark.coordinate, application: self.application)
            self.application.viewRouter.navigate(to: nearbyStops, from: self)
        }
    }
}
