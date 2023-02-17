//
//  RegionProvider.swift
//  OBAKit
//
//  Created by Alan Chu on 1/23/23.
//

import OBAKitCore

public protocol RegionProvider: ObservableObject {
    /// OBA-regions and custom regions.
    var allRegions: [Region] { get }
    var currentRegion: Region? { get }

    var automaticallySelectRegion: Bool { get set }

    func refreshRegions() async throws

    /// A ``currentRegion`` setter that is `async throws`.
    func setCurrentRegion(to newRegion: Region) async throws

    /// Adds the provided custom region to the RegionsService.
    func add(customRegion newRegion: Region) async throws

    /// Deletes the provided custom region.
    func delete(customRegion region: Region) async throws
}
