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
import IGListKit
import SafariServices
import OBAKitCore

class MapItemViewController: VisualEffectViewController,
    AppContext,
    ListAdapterDataSource,
    Scrollable {

    /// The OBA application object
    let application: Application

    lazy var titleView = FloatingPanelTitleView.autolayoutNew()

    var scrollView: UIScrollView { collectionController.collectionView }

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

        prepareChildController(collectionController) {
            let stack = UIStackView.verticalStack(arrangedSubviews: [
                titleView, collectionController.view
            ])
            visualEffectView.contentView.addSubview(stack)
            stack.pinToSuperview(.edges)
        }
    }

    // MARK: - IGListKit

    private var aboutSection: [ListDiffable] {
        var rows = [TableRowData]()

        if let address = mapItem.placemark.postalAddress {
            let formattedAddress = CNPostalAddressFormatter.string(from: address, style: .mailingAddress)
            let row = TableRowData(title: formattedAddress, accessoryType: .none) { [weak self] _ in
                guard let self = self else { return }
                self.mapItem.openInMaps(launchOptions: nil)
            }
            rows.append(row)
        }

        if let phone = mapItem.phoneNumber, let url = URL(phoneNumber: phone) {
            let row = TableRowData(title: phone, accessoryType: .none) { [weak self] _ in
                guard let self = self else { return }
                self.application.open(url, options: [:], completionHandler: nil)
            }
            rows.append(row)
        }

        if let url = mapItem.url {
            let row = TableRowData(title: url.absoluteString, accessoryType: .none) { [weak self] _ in
                guard let self = self else { return }
                let safari = SFSafariViewController(url: url)
                self.application.viewRouter.present(safari, from: self)
            }
            rows.append(row)
        }

        return [
            TableHeaderData(title: OBALoc("map_item_controller.about_header", value: "About", comment: "about section header")),
            TableSectionData(rows: rows)
        ]
    }

    private var moreSection: [ListDiffable] {
        let row = TableRowData(title: OBALoc("map_item_controller.nearby_stops_row", value: "Nearby Stops", comment: "A table row that shows stops nearby."), accessoryType: .disclosureIndicator) { [weak self] _ in
            guard let self = self else { return }
            let nearbyStops = NearbyStopsViewController(coordinate: self.mapItem.placemark.coordinate, application: self.application)
            self.application.viewRouter.navigate(to: nearbyStops, from: self)
        }
        return [
            TableHeaderData(title: OBALoc("map_item_controller.more_header", value: "More", comment: "More options header")),
            TableSectionData(row: row)
        ]
    }

    func objects(for listAdapter: ListAdapter) -> [ListDiffable] {
        var sections = [ListDiffable]()
        sections.append(contentsOf: aboutSection)
        sections.append(contentsOf: moreSection)
        return sections
    }

    func listAdapter(_ listAdapter: ListAdapter, sectionControllerFor object: Any) -> ListSectionController {
        return defaultSectionController(for: object)
    }

    func emptyView(for listAdapter: ListAdapter) -> UIView? {
        return nil
    }

    private lazy var collectionController: CollectionController = {
        let controller = CollectionController(application: application, dataSource: self)
        controller.collectionView.showsVerticalScrollIndicator = false
        return controller
    }()
}
