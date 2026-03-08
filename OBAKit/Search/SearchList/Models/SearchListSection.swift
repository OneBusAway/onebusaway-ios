//
//  SearchListSection.swift
//  OBAKit
//
//  Created by Mohamed Sliem on 07/03/2026.
//

import Foundation

struct SearchListSection: Identifiable {
    typealias ID = SearchListSectionType

    var id: ID

    var title: String

    var content: [SearchListRow]

}

enum SearchListSectionType: String, Hashable {
    case recentStops
    case recentMapItems
    case bookmarks
    case quickSearch
    case placemarks
}
