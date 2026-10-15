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

    // MARK: - LabelText

    @Test func testLabelTextStringEqualityAndHash() {
        let text1 = OBAListRowConfiguration.LabelText.string("Station")
        let text2 = OBAListRowConfiguration.LabelText.string("Station")
        let text3 = OBAListRowConfiguration.LabelText.string("Other")
        let nilText1 = OBAListRowConfiguration.LabelText.string(nil)
        let nilText2 = OBAListRowConfiguration.LabelText.string(nil)

        #expect(text1 == text2)
        #expect(text1.hashValue == text2.hashValue)
        #expect(text1 != text3)
        #expect(nilText1 == nilText2)
        #expect(nilText1.hashValue == nilText2.hashValue)
        #expect(text1 != nilText1)
    }

    @Test func testLabelTextAttributedEqualityAndHash() {
        let attr1 = NSAttributedString(string: "Bold Station", attributes: [.strokeWidth: 2])
        let attr2 = NSAttributedString(string: "Bold Station", attributes: [.strokeWidth: 2])
        let attr3 = NSAttributedString(string: "Italic Station", attributes: [.obliqueness: 0.5])

        let label1 = OBAListRowConfiguration.LabelText.attributed(attr1)
        let label2 = OBAListRowConfiguration.LabelText.attributed(attr2)
        let label3 = OBAListRowConfiguration.LabelText.attributed(attr3)
        let nilAttr1 = OBAListRowConfiguration.LabelText.attributed(nil)
        let nilAttr2 = OBAListRowConfiguration.LabelText.attributed(nil)

        #expect(label1 == label2)
        #expect(label1.hashValue == label2.hashValue)
        #expect(label1 != label3)
        #expect(nilAttr1 == nilAttr2)
        #expect(nilAttr1.hashValue == nilAttr2.hashValue)
        #expect(label1 != nilAttr1)
    }

    @Test func testLabelTextCrossVariantInequality() {
        let stringVariant = OBAListRowConfiguration.LabelText.string("Route 44")
        let attributedVariant = OBAListRowConfiguration.LabelText.attributed(NSAttributedString(string: "Route 44"))

        #expect(stringVariant != attributedVariant)
    }

    // MARK: - OBAListRowSeparatorConfiguration

    @Test func testSeparatorConfigurationInitializers() {
        let defaultSep = OBAListRowSeparatorConfiguration()
        #expect(defaultSep.showsSeparator == true)
        #expect(defaultSep.insets == .zero)

        let hiddenSep = OBAListRowSeparatorConfiguration.hidden()
        #expect(hiddenSep.showsSeparator == false)
        #expect(hiddenSep.insets == .zero)

        let customInsets = NSDirectionalEdgeInsets(top: 2, leading: 16, bottom: 4, trailing: 20)
        let insetSep = OBAListRowSeparatorConfiguration.withInset(top: 2, leading: 16, bottom: 4, trailing: 20)
        #expect(insetSep.showsSeparator == true)
        #expect(insetSep.insets == customInsets)

        #expect(defaultSep != hiddenSep)
        #expect(defaultSep != insetSep)
        #expect(defaultSep == OBAListRowSeparatorConfiguration(showsSeparator: true, insets: .zero))
    }

    @Test func testUIListSeparatorConfigurationApplying() {
        var listSepConfig = UIListSeparatorConfiguration(listAppearance: .plain)

        let visibleConfig = OBAListRowSeparatorConfiguration(
            showsSeparator: true,
            insets: NSDirectionalEdgeInsets(top: 1, leading: 10, bottom: 2, trailing: 12)
        )
        listSepConfig.applying(visibleConfig)
        #expect(listSepConfig.topSeparatorVisibility == .automatic)
        #expect(listSepConfig.bottomSeparatorVisibility == .automatic)
        #expect(listSepConfig.topSeparatorInsets == visibleConfig.insets)
        #expect(listSepConfig.bottomSeparatorInsets == visibleConfig.insets)

        let hiddenConfig = OBAListRowSeparatorConfiguration.hidden()
        listSepConfig.applying(hiddenConfig)
        #expect(listSepConfig.topSeparatorVisibility == .hidden)
        #expect(listSepConfig.bottomSeparatorVisibility == .hidden)
    }
}
