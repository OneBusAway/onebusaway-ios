//
//  OBAListRowConfigurationTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
import UIKit
@testable import OBAKit
@testable import OBAKitCore

@MainActor
@Suite(.serialized)
struct OBAListRowConfigurationTests {

    // MARK: - OBAListRowConfiguration Initialization & Properties

    @Test func testDefaultInitialization() {
        let config = OBAListRowConfiguration()
        #expect(config.formatters == nil)
        #expect(config.image == nil)
        #expect(config.imageConfig == OBAImageViewConfiguration())
        #expect(config.text == nil)
        #expect(config.secondaryText == nil)
        #expect(config.textConfig == OBALabelConfiguration())
        #expect(config.secondaryTextConfig == OBALabelConfiguration(textColor: .secondaryLabel))
        #expect(config.appearance == .default)
        #expect(config.accessoryType == .none)
    }

    @Test func testMinimumCellHeight() {
        var config = OBAListRowConfiguration()

        config.appearance = .header
        #expect(config.minimumCellHeight == 0)

        config.appearance = .default
        #expect(config.minimumCellHeight == 44.0)

        config.appearance = .subtitle
        #expect(config.minimumCellHeight == 44.0)

        config.appearance = .value
        #expect(config.minimumCellHeight == 44.0)
    }

    @Test func testListConfigurationAppearances() {
        var config = OBAListRowConfiguration()

        config.appearance = .default
        _ = config.listConfiguration

        config.appearance = .subtitle
        _ = config.listConfiguration

        config.appearance = .value
        _ = config.listConfiguration

        config.appearance = .header
        _ = config.listConfiguration
    }

    @Test func testListConfigurationPropertiesPropagation() {
        var config = OBAListRowConfiguration()
        let image = UIImage()
        config.image = image
        config.imageConfig = OBAImageViewConfiguration(tintColor: .systemRed, maximumSize: CGSize(width: 28, height: 28))
        config.text = .string("Primary Title")
        config.secondaryText = .string("Secondary Detail")
        config.textConfig = OBALabelConfiguration(textColor: .systemBlue, numberOfLines: 2, accessibilityNumberOfLines: 4)
        config.secondaryTextConfig = OBALabelConfiguration(textColor: .systemGray, numberOfLines: 1, accessibilityNumberOfLines: 2)
        config.appearance = .subtitle

        let listConfig = config.listConfiguration

        #expect(listConfig.image == image)
        #expect(listConfig.imageProperties.tintColor == .systemRed)
        #expect(listConfig.imageProperties.maximumSize == CGSize(width: 28, height: 28))
        #expect(listConfig.labelText == .string("Primary Title"))
        #expect(listConfig.secondaryLabelText == .string("Secondary Detail"))
        #expect(listConfig.textProperties.color == .systemBlue)
        #expect(listConfig.textProperties.numberOfLines == 2)
        #expect(listConfig.secondaryTextProperties.color == .systemGray)
        #expect(listConfig.secondaryTextProperties.numberOfLines == 1)
        #expect(listConfig.textToSecondaryTextVerticalPadding == ThemeMetrics.compactPadding)
    }

    @Test func testAccessoryCellAccessoryMapping() {
        #expect(OBAListRowConfiguration.Accessory.none.cellAccessory == nil)

        let checkmarkAccessory = OBAListRowConfiguration.Accessory.checkmark.cellAccessory
        #expect(checkmarkAccessory != nil)
        #expect(checkmarkAccessory is UICellAccessory.Checkmark)
        #expect(checkmarkAccessory?.displayed == .always)

        let disclosureAccessory = OBAListRowConfiguration.Accessory.disclosureIndicator.cellAccessory
        #expect(disclosureAccessory != nil)
        #expect(disclosureAccessory is UICellAccessory.DisclosureIndicator)
        #expect(disclosureAccessory?.displayed == .always)
    }

    @Test func testEquality() {
        let imageA = UIImage()
        let imageB = UIImage()

        let base = OBAListRowConfiguration(
            image: imageA,
            text: .string("Title"),
            secondaryText: .string("Subtitle"),
            appearance: .subtitle,
            accessoryType: .checkmark
        )

        let identical = base
        #expect(base == identical)

        var differentImage = base
        differentImage.image = imageB
        #expect(base != differentImage)

        var differentText = base
        differentText.text = .string("Changed")
        #expect(base != differentText)

        var differentSecondary = base
        differentSecondary.secondaryText = .string("Changed")
        #expect(base != differentSecondary)

        var differentAppearance = base
        differentAppearance.appearance = .default
        #expect(base != differentAppearance)

        var differentAccessory = base
        differentAccessory.accessoryType = .disclosureIndicator
        #expect(base != differentAccessory)

        var differentImageConfig = base
        differentImageConfig.imageConfig = .tinted(.red)
        #expect(base != differentImageConfig)

        var differentTextConfig = base
        differentTextConfig.textConfig = OBALabelConfiguration(textColor: .green)
        #expect(base != differentTextConfig)

        var differentSecTextConfig = base
        differentSecTextConfig.secondaryTextConfig = OBALabelConfiguration(textColor: .yellow)
        #expect(base != differentSecTextConfig)
    }
}
