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

    public let appearance: ListAppearance

    public init(appearance: ListAppearance = .plain) {
        self.appearance = appearance
    }

    static public func appearance(_ appearance: ListAppearance) -> Self {
        return .init(appearance: appearance)
    }

    func listConfiguration() -> UICollectionLayoutListConfiguration {
        let appearance: UICollectionLayoutListConfiguration.Appearance
        switch self.appearance {
        case .plain:        appearance = .plain
        case .insetGrouped: appearance = .insetGrouped
        }

        return .init(appearance: appearance)
    }
}
