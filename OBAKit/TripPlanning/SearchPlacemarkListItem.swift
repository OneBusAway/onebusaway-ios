//
//  SearchPlacemarkListItem.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 9/6/25.
//

import MapKit
import OBAKitCore

final class SearchPlacemarkTableCell: OBAListViewCell {
    override init(frame: CGRect) {
        super.init(frame: frame)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func apply(_ config: OBAContentConfiguration) {
        guard let config = config as? SearchPlacemarkContentConfiguration else { return }

        // TODO: create UI for this cell.
        // TODO: fill in the UI from the viewModel and its MKMapItem.
    }

}

struct SearchPlacemarkContentConfiguration: OBAContentConfiguration {
    var formatters: Formatters?

    var viewModel: SearchPlacemarkViewModel

    var obaContentView: (OBAContentView & ReuseIdentifierProviding).Type {
        return SearchPlacemarkTableCell.self
    }
}

struct SearchPlacemarkViewModel: OBAListViewItem {
    // MARK: - View model properties
    let id = UUID()
    let mapItem: MKMapItem

    static var customCellType: OBAListViewCell.Type? {
        return SearchPlacemarkTableCell.self
    }

    var configuration: OBAListViewItemConfiguration {
        return .custom(SearchPlacemarkContentConfiguration(viewModel: self))
    }

    var onSelectAction: OBAListViewAction<SearchPlacemarkViewModel>?

    init(mapItem: MKMapItem,
         onSelect: OBAListViewAction<SearchPlacemarkViewModel>?) {
        self.mapItem = mapItem
        self.onSelectAction = onSelect
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(mapItem)
    }

    static func == (lhs: SearchPlacemarkViewModel, rhs: SearchPlacemarkViewModel) -> Bool {
        return lhs.id == rhs.id && lhs.mapItem == rhs.mapItem
    }
}
