//
//  OBAListSectionConfiguration.swift
//  OBAKit
//
//  Created by Alan Chu on 6/20/21.
//

public struct OBAListSectionConfiguration: Equatable {
    public enum ListAppearance: Equatable {
        case plain
        case insetGrouped
    }

    public var appearance: ListAppearance

    /// Note, per `UICollectionLayoutListConfiguration`, a value of `nil` means that the configuration uses the system background color.
    public var backgroundColor: UIColor?

    // MARK: - Initializers
    public init(appearance: ListAppearance = .plain, backgroundColor: UIColor? = nil) {
        self.appearance = appearance
        self.backgroundColor = nil
    }

    static public func appearance(_ appearance: ListAppearance) -> Self {
        return .init(appearance: appearance)
    }

    // MARK: - UIKit
    func listConfiguration() -> UICollectionLayoutListConfiguration {
        let appearance: UICollectionLayoutListConfiguration.Appearance
        switch self.appearance {
        case .plain:        appearance = .plain
        case .insetGrouped: appearance = .insetGrouped
        }

        var config = UICollectionLayoutListConfiguration(appearance: appearance)
        config.backgroundColor = self.backgroundColor
        return config
    }
}
