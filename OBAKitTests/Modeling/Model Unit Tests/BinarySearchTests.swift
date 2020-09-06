//
//  BinarySearchTests.swift
//  OBAKitTests
//
//  Created by Alan Chu on 8/23/20.
//

import XCTest
import Nimble
@testable import OBAKit
@testable import OBAKitCore

class BinarySearchTests: OBATestCase {
    struct Person {
        var id: String
        var name: String
    }

    func testBinarySearch() {
        let people: [Person] = [
            .init(id: "43", name: "Bob"),
            .init(id: "33", name: "Rob"),
            .init(id: "12", name: "Job"),
            .init(id: "35", name: "Lob"),
            .init(id: "49", name: "Nob")
        ]

        let sortedByID = people.sorted { $0.id < $1.id }
        let sortedByName = people.sorted { $0.name < $1.name }

        expect(sortedByID.binarySearch(sortedBy: \.id, element: "35")?.element.name).to(equal("Lob"))
        expect(sortedByID.binarySearch(sortedBy: \.id, element: "12")?.element.name).to(equal("Job"))

        expect(sortedByName.binarySearch(sortedBy: \.name, element: "Nob")?.element.id).to(equal("49"))
        expect(sortedByName.binarySearch(sortedBy: \.name, element: "Bob")?.element.id).to(equal("43"))
    }
}
