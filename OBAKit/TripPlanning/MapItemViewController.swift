//
//  MapItemViewController.swift
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

class MapItemViewController: VisualEffectViewController,
    AppContext,
    OBAListViewDataSource,
    Scrollable {

    /// The OBA application object
    let application: Application

    lazy var titleView = FloatingPanelTitleView.autolayoutNew()
    let listView = OBAListView()

    var scrollView: UIScrollView { listView }

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

        titleView.titleLabel.text = mapItem.name ?? ""
        titleView.closeButton.addTarget(self, action: #selector(close), for: .touchUpInside)

        listView.obaDataSource = self
        listView.showsVerticalScrollIndicator = false
        listView.backgroundColor = .clear

        let stack = UIStackView.verticalStack(arrangedSubviews: [titleView, listView])
        visualEffectView.contentView.addSubview(stack)

        let insets = NSDirectionalEdgeInsets(top: ThemeMetrics.padding, leading: 0, bottom: 0, trailing: 0)
        stack.pinToSuperview(.edges, insets: insets)

        listView.applyData()
    }

    // MARK: - OBAListView

    private var aboutSection: OBAListViewSection {
        var rows: [AnyOBAListViewItem] = []
        if let address = mapItem.placemark.postalAddress {
            let formattedAddress = CNPostalAddressFormatter.string(from: address, style: .mailingAddress)
            let row = OBAListRowView.DefaultViewModel(title: formattedAddress, accessoryType: .none) { _ in
                self.mapItem.openInMaps(launchOptions: nil)
            }
            rows.append(row.typeErased)
        }

        if let phone = mapItem.phoneNumber, let url = URL(phoneNumber: phone) {
            let row = OBAListRowView.DefaultViewModel(title: phone, accessoryType: .none) { _ in
                self.application.open(url, options: [:], completionHandler: nil)
            }
            rows.append(row.typeErased)
        }

        if let url = mapItem.url {
            let row = OBAListRowView.DefaultViewModel(title: url.absoluteString, accessoryType: .none) { _ in
                let safari = SFSafariViewController(url: url)
                self.application.viewRouter.present(safari, from: self)
            }
            rows.append(row.typeErased)
        }

        return OBAListViewSection(id: "about", title: OBALoc("map_item_controller.about_header", value: "About", comment: "about section header"), contents: rows)
    }

    private var moreSection: OBAListViewSection {
        let row = OBAListRowView.DefaultViewModel(title: OBALoc("map_item_controller.nearby_stops_row", value: "Nearby Stops", comment: "A table row that shows stops nearby."), accessoryType: .disclosureIndicator) { _ in
            let nearbyStops = NearbyStopsViewController(coordinate: self.mapItem.placemark.coordinate, application: self.application)
            self.application.viewRouter.navigate(to: nearbyStops, from: self)
        }

        return OBAListViewSection(id: "more", title: OBALoc("map_item_controller.more_header", value: "More", comment: "More options header"), contents: [row])
    }

    func items(for listView: OBAListView) -> [OBAListViewSection] {
        return [aboutSection, moreSection]
    }
}
