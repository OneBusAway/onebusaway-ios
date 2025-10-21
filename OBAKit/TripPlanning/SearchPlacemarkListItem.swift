//
//  SearchPlacemarkListItem.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 9/6/25.
//

import UIKit
import MapKit
import OBAKitCore

final private class SearchPlacemarkView: UIView {
    let titleLabel: UILabel = {
        let label = UILabel.autolayoutNew()
        label.font = .preferredFont(forTextStyle: .body).bold
        return label
    }()

    let addressLabel: UILabel = {
        let label = UILabel.autolayoutNew()
        label.textColor = ThemeColors.shared.secondaryLabel
        return label
    }()

    let poiCategoryImageView: UIImageView = {
        let v = UIImageView.autolayoutNew()
        v.contentMode = .scaleAspectFit
        return v
    }()

    var outerStackView: UIStackView
    var labelStackView: UIStackView

    override init(frame: CGRect) {
        labelStackView = UIStackView.verticalStack(arrangedSubviews: [titleLabel, addressLabel])
        labelStackView.spacing = ThemeMetrics.compactPadding

        outerStackView = UIStackView.horizontalStack(arrangedSubviews: [poiCategoryImageView, labelStackView])
        outerStackView.spacing = ThemeMetrics.padding

        super.init(frame: frame)
        addSubview(outerStackView)
        outerStackView.pinToSuperview(.layoutMargins, insets: NSDirectionalEdgeInsets(
            top: 0,
            leading: 0,
            bottom: 0,
            trailing: 0
        ))
        NSLayoutConstraint.activate([
            poiCategoryImageView.widthAnchor.constraint(equalToConstant: SearchPlacemarkTableCell.iconSize)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

#Preview {
    let view = SearchPlacemarkView(frame: CGRect(x: 0, y: 0, width: 320, height: 44))
    view.poiCategoryImageView.image = UIImage(systemName: "bus")
    view.titleLabel.text = "title label"
    view.addressLabel.text = "address label"
    return view
}

final class SearchPlacemarkTableCell: OBAListViewCell {
    fileprivate static let iconSize = 32.0
    fileprivate let innerView = SearchPlacemarkView(frame: .zero)
    private let badgeRenderer = ImageBadgeRenderer(fillColor: .white, backgroundColor: ThemeColors.shared.brand, badgeSize: iconSize)

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.addSubview(innerView)
        innerView.pinToSuperview(.edges)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func apply(_ config: OBAContentConfiguration) {
        guard let config = config as? SearchPlacemarkContentConfiguration else { return }
        let mapItem = config.viewModel.mapItem

        innerView.titleLabel.text = mapItem.name

        if #available(iOS 26.0, *) {
            innerView.addressLabel.text = mapItem.address?.shortAddress
        } else {
            let pm = mapItem.placemark
            let parts = [pm.subThoroughfare, pm.thoroughfare, pm.locality, pm.subAdministrativeArea, pm.administrativeArea, pm.postalCode]
            innerView.addressLabel.text = parts.compactMap { $0 }.joined(separator: " ")
        }

        if let poi = mapItem.pointOfInterestCategory, let symbol = UIImage(systemName: poi.symbolName) {
            innerView.poiCategoryImageView.image = badgeRenderer.drawImageOnRoundedRect(symbol)
        }
        else {
            innerView.poiCategoryImageView.image = badgeRenderer.drawImageOnRoundedRect(UIImage(systemName: "mappin")!)
        }
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
