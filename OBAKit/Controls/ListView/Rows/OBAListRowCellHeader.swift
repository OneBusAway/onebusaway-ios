//
//  OBAListRowCellHeader.swift
//  OBAKit
//
//  Created by Alan Chu on 10/4/20.
//

import OBAKitCore

public class OBAListRowCellHeader: OBAListRowView {
    static let ReuseIdentifier: String = "OBAListRowCellDefault_ReuseIdentifier"

    let titleLabel: UILabel = .obaLabel(font: .preferredFont(forTextStyle: .body))

    override func makeUserView() -> UIView {
        // wrap in stack view to fix layout spacing
        return UIStackView(arrangedSubviews: [titleLabel])
    }

    override func configureView() {
        super.configureView()
        self.backgroundColor = UIColor.secondarySystemBackground

        titleLabel.text = configuration.text
    }
}

// MARK: - UICollectionReusableView
public protocol OBAListRowHeaderSupplementaryViewDelegate: class {
    func didTap(_ headerView: OBAListRowHeaderSupplementaryView, section: OBAListViewSection)
}

public class OBAListRowHeaderSupplementaryView: UICollectionReusableView {
    static let ReuseIdentifier: String = "OBAListRowHeaderSupplementaryView_ReuseIdentifier"

    // MARK: - Properties to set
    public weak var delegate: OBAListRowHeaderSupplementaryViewDelegate?
    public var section: OBAListViewSection? {
        didSet {
            guard let section = section else { return }

            if let collapseState = section.collapseState {
                let image: UIImage

                switch collapseState {
                case .collapsed:    image = UIImage(systemName: "chevron.right.circle.fill")!
                case .expanded:     image = UIImage(systemName: "chevron.down.circle.fill")!
                }

                headerView.configuration = OBAListContentConfiguration(image: image, text: section.title, appearance: .header)
            } else {
                headerView.configuration = OBAListContentConfiguration(text: section.title, appearance: .header)
            }
        }
    }

    // MARK: - UI
    fileprivate var headerView: OBAListRowCellHeader = OBAListRowCellHeader(frame: .zero)

    public override init(frame: CGRect) {
        super.init(frame: frame)

        addSubview(headerView)
        headerView.pinToSuperview(.edges)

        let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(didTap))
        addGestureRecognizer(tapGestureRecognizer)
    }

    @objc func didTap(_ sender: UITapGestureRecognizer) {
        guard let section = section else { return }
        self.delegate?.didTap(self, section: section)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

// MARK: - Preview
#if DEBUG
import SwiftUI
import OBAKitCore

struct OBAListRowCellHeader_Previews: PreviewProvider {
    static let configuration = OBAListContentConfiguration(image: UIImage(systemName: "person.circle.fill"), text: "Privacy Settings", appearance: .header, accessoryType: .none)

    static var previews: some View {
        Group {
            UIViewPreview {
                let view = OBAListRowCellHeader(frame: .zero)
                view.configuration = configuration
                return view
            }
            .previewLayout(.fixed(width: 384, height: 44))

            UIViewPreview {
                let view = OBAListRowCellHeader(frame: .zero)
                view.configuration = configuration
                return view
            }
            .environment(\.sizeCategory, .accessibilityLarge)
            .previewLayout(.sizeThatFits)
        }
    }
}

#endif
