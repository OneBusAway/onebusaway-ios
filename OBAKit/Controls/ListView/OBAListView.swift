//
//  OBAListView.swift
//  OBAKit
//
//  Created by Alan Chu on 9/30/20.
//

/// Displays information as a vertical-scrolling list, a la TableView.
///
/// There are two separate `OBAListViewConfigurator`s under-the-hood. One is for iOS 14+, the other
/// is for iOS 13.  iOS 14 uses `UICollectionLayoutListConfiguration` because its user experience
/// is much better than our custom table view-like implementation. The purpose of `OBAList` is to abstract
/// this platform-specific code away from the rest of the application.
///
/// This architecture prepares us for the deprecation of our custom implementation when we drop iOS 13.
///
/// There are a number of "bridging" models that mimic iOS 14 functionality for iOS 13. See the `Bridge`
/// subfolder for examples.
public class OBAListView: UICollectionView {
    fileprivate var underlyingConfigurator: OBAListViewConfigurator
    fileprivate var diffableDataSource: UICollectionViewDiffableDataSource<OBAListViewSection, AnyOBAListViewItem>!

    public convenience init() {
        let configurator: OBAListViewConfigurator
        if #available(iOS 14, *) {
            configurator = OBAListViewUsingListConfiguration()
        } else {
            configurator = OBAListViewUsingOBA()
        }

        self.init(configurator: configurator)
    }

    init(configurator: OBAListViewConfigurator) {
        self.underlyingConfigurator = configurator
        super.init(frame: .zero, collectionViewLayout: configurator.createLayout())

        self.underlyingConfigurator.registerCells(self)
        self.diffableDataSource = configurator.createDataSource(self)
        self.dataSource = self.diffableDataSource

        self.backgroundColor = .systemBackground
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// - precondition: The `id` of each `OBAListViewSection` must be unique.
    public func sectionsForList() -> [OBAListViewSection] {
        fatalError("OBAListView.sectionsForList() called, without a proper implementation.")
    }

    public func applyData() {
        var snapshot = NSDiffableDataSourceSnapshot<OBAListViewSection, AnyOBAListViewItem>()
        let sections = self.sectionsForList()

        snapshot.appendSections(sections)
        for section in sections {
            snapshot.appendItems(section.listViewItems, toSection: section)
        }

        self.diffableDataSource.apply(snapshot)
    }
}

// MARK: - Preview
#if DEBUG
import SwiftUI
import OBAKitCore

struct OBAListView_Previews: PreviewProvider {
    private static let personsListView = PersonsListView()
    private static let fallbackListView = PersonsListView(configurator: OBAListViewUsingOBA())

    static var previews: some View {
        Group {
            UIViewPreview {
                personsListView
            }
            .onAppear { personsListView.applyData() }
            .previewDisplayName("iOS 14+")

            UIViewPreview {
                fallbackListView
            }
            .onAppear { fallbackListView.applyData() }
            .previewDisplayName("iOS 13")
        }
    }
}

private struct Person: OBAListViewItem {
    var name: String
    var address: String

    func listViewConfigurationForThisItem(_ listView: OBAListView) -> OBAListContentConfiguration {
        return OBAListContentConfiguration(image: UIImage(systemName: "person.fill"), text: name, secondaryText: address, appearance: .subtitle, accessoryType: .none)
    }
}

private class PersonsListView: OBAListView {
    override func sectionsForList() -> [OBAListViewSection] {
        [
            OBAListViewSection(id: "1", title: "B", contents: [
                Person(name: "Bo", address: "123 Main St"),
                Person(name: "Bob", address: "456 Broadway"),
                Person(name: "Bobby", address: "asdfasdkfjad")
            ]),
            OBAListViewSection(id: "2", title: "C", contents: [
                Person(name: "Ca", address: "193 Lochmere Ln"),
                Person(name: "Cab", address: "anywhere u want"),
                Person(name: "Cabby", address: "huh")
            ])
        ]
    }
}
#endif
