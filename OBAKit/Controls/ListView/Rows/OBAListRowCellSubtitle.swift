//
//  OBAListRowCellSubtitle.swift
//  OBAKit
//
//  Created by Alan Chu on 10/4/20.
//

public class OBAListRowCellSubtitle: OBAListRowView {
    static let ReuseIdentifier: String = "OBAListRowCellSubtitle_ReuseIdentifier"
    private var textStack: UIStackView!

    let titleLabel: UILabel = .obaLabel(font: .preferredFont(forTextStyle: .body))
    let subtitleLabel: UILabel = .obaLabel(font: .preferredFont(forTextStyle: .footnote), textColor: ThemeColors.shared.secondaryLabel)

    override func makeUserView() -> UIView {
        self.textStack = UIStackView.stack(axis: .vertical, distribution: .fill, arrangedSubviews: [titleLabel, subtitleLabel])

        return self.textStack
    }

    override func configureView() {
        super.configureView()
        titleLabel.text = configuration.text
        subtitleLabel.text = configuration.secondaryText
    }
}

// MARK: - Preview
#if DEBUG
import SwiftUI
import OBAKitCore

struct OBAListRowCellSubtitle_Previews: PreviewProvider {
    static let configuration = OBAListContentConfiguration(image: UIImage(systemName: "person.fill"), text: "name", secondaryText: "address", appearance: .subtitle, accessoryType: .none)
    static var previews: some View {
        Group {
            UIViewPreview {
                let view = OBAListRowCellSubtitle()
                view.configuration = configuration
                return view
            }
            .previewLayout(.fixed(width: 384, height: 44))
        }
    }
}

#endif
