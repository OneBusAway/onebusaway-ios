//
//  MigrationModelTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
@testable import OBAKitCore

@Suite(.serialized)
final class MigrationModelTests {
    @objc(DummyRecentStop) final class DummyRecentStop: NSObject, NSCoding {
        func encode(with coder: NSCoder) {
            coder.encode("Main St", forKey: "title")
            coder.encode("Bound for Downtown", forKey: "subtitle")
            coder.encode("1_1020", forKey: "stopID")
            coder.encode(47.6, forKey: "latitude")
            coder.encode(-122.3, forKey: "longitude")
        }
        required init?(coder: NSCoder) { nil }
        override init() { super.init() }
    }

    @objc(DummyRegion) final class DummyRegion: NSObject, NSCoding {
        func encode(with coder: NSCoder) {
            coder.encode("Seattle", forKey: "regionName")
            coder.encode(1, forKey: "identifier")
        }
        required init?(coder: NSCoder) { nil }
        override init() { super.init() }
    }

    @objc(DummyBookmark) final class DummyBookmark: NSObject, NSCoding {
        func encode(with coder: NSCoder) {
            coder.encode("Home", forKey: "name")
            coder.encode("1_100", forKey: "stopId")
            coder.encode(1, forKey: "regionIdentifier")
            coder.encode("10", forKey: "routeShortName")
            coder.encode("Downtown", forKey: "tripHeadsign")
            coder.encode("1_10", forKey: "routeID")
            coder.encode(3, forKey: "sortOrder")
        }
        required init?(coder: NSCoder) { nil }
        override init() { super.init() }
    }

    @objc(DummyBookmarkGroup) final class DummyBookmarkGroup: NSObject, NSCoding {
        let bookmarks: [DummyBookmark]
        init(bookmarks: [DummyBookmark]) {
            self.bookmarks = bookmarks
            super.init()
        }
        func encode(with coder: NSCoder) {
            coder.encode("Work", forKey: "name")
            coder.encode("abcd-1234", forKey: "UUID")
            coder.encode(bookmarks, forKey: "bookmarks")
            coder.encode(1, forKey: "bookmarkGroupType")
            coder.encode(true, forKey: "open")
            coder.encode(2, forKey: "sortOrder")
        }
        required init?(coder: NSCoder) { nil }
    }

    @Test func MigrationRecentStop decodes correctly() throws {
        let dummy = DummyRecentStop()
        let archiver = NSKeyedArchiver(requiringSecureCoding: false)
        archiver.setClassName("MigrationRecentStop", for: DummyRecentStop.self)
        archiver.encode(dummy, forKey: NSKeyedArchiveRootObjectKey)
        archiver.finishEncoding()
        
        let data = archiver.encodedData
        
        let unarchiver = try NSKeyedUnarchiver(forReadingFrom: data)
        unarchiver.requiresSecureCoding = false
        unarchiver.setClass(MigrationRecentStop.self, forClassName: "MigrationRecentStop")
        
        let decoded = unarchiver.decodeObject(forKey: NSKeyedArchiveRootObjectKey) as? MigrationRecentStop
        #expect(decoded != nil)
        #expect(decoded?.title == "Main St")
        #expect(decoded?.subtitle == "Bound for Downtown")
        #expect(decoded?.stopID == "1_1020")
        #expect(decoded?.coordinate.latitude == 47.6)
        #expect(decoded?.coordinate.longitude == -122.3)
    }

    @Test func MigrationRegion decodes correctly() throws {
        let dummy = DummyRegion()
        let archiver = NSKeyedArchiver(requiringSecureCoding: false)
        archiver.setClassName("MigrationRegion", for: DummyRegion.self)
        archiver.encode(dummy, forKey: NSKeyedArchiveRootObjectKey)
        archiver.finishEncoding()
        
        let data = archiver.encodedData
        
        let unarchiver = try NSKeyedUnarchiver(forReadingFrom: data)
        unarchiver.requiresSecureCoding = false
        unarchiver.setClass(MigrationRegion.self, forClassName: "MigrationRegion")
        
        let decoded = unarchiver.decodeObject(forKey: NSKeyedArchiveRootObjectKey) as? MigrationRegion
        #expect(decoded != nil)
        #expect(decoded?.name == "Seattle")
        #expect(decoded?.identifier == 1)
    }

    @Test func MigrationBookmark decodes correctly() throws {
        let dummy = DummyBookmark()
        let archiver = NSKeyedArchiver(requiringSecureCoding: false)
        archiver.setClassName("MigrationBookmark", for: DummyBookmark.self)
        archiver.encode(dummy, forKey: NSKeyedArchiveRootObjectKey)
        archiver.finishEncoding()
        
        let data = archiver.encodedData
        
        let unarchiver = try NSKeyedUnarchiver(forReadingFrom: data)
        unarchiver.requiresSecureCoding = false
        unarchiver.setClass(MigrationBookmark.self, forClassName: "MigrationBookmark")
        
        let decoded = unarchiver.decodeObject(forKey: NSKeyedArchiveRootObjectKey) as? MigrationBookmark
        #expect(decoded != nil)
        #expect(decoded?.name == "Home")
        #expect(decoded?.stopID == "1_100")
        #expect(decoded?.regionID == 1)
        #expect(decoded?.routeShortName == "10")
        #expect(decoded?.tripHeadsign == "Downtown")
        #expect(decoded?.routeID == "1_10")
        #expect(decoded?.sortOrder == 3)
        #expect(decoded?.isStopBookmark == false)
    }

    @Test func MigrationBookmarkGroup decodes correctly() throws {
        let dummy = DummyBookmarkGroup(bookmarks: [DummyBookmark()])
        let archiver = NSKeyedArchiver(requiringSecureCoding: false)
        archiver.setClassName("MigrationBookmarkGroup", for: DummyBookmarkGroup.self)
        archiver.setClassName("MigrationBookmark", for: DummyBookmark.self)
        archiver.encode(dummy, forKey: NSKeyedArchiveRootObjectKey)
        archiver.finishEncoding()
        
        let data = archiver.encodedData
        
        let unarchiver = try NSKeyedUnarchiver(forReadingFrom: data)
        unarchiver.requiresSecureCoding = false
        unarchiver.setClass(MigrationBookmarkGroup.self, forClassName: "MigrationBookmarkGroup")
        unarchiver.setClass(MigrationBookmark.self, forClassName: "MigrationBookmark")
        
        let decoded = unarchiver.decodeObject(forKey: NSKeyedArchiveRootObjectKey) as? MigrationBookmarkGroup
        #expect(decoded != nil)
        #expect(decoded?.name == "Work")
        #expect(decoded?.uuid == "abcd-1234")
        #expect(decoded?.todayScreenVisible == true)
        #expect(decoded?.open == true)
        #expect(decoded?.sortOrder == 2)
        #expect(decoded?.bookmarks.count == 1)
        #expect(decoded?.bookmarks.first?.name == "Home")
    }
}
