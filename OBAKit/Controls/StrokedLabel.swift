//
//  StrokedLabel.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 10/28/25.
//

/// A UILabel subclass that correctly renders negative stroke values.
///
/// Derived from here: https://gist.github.com/eeshishko/4835ee15590b626d69976b86bc644953
/// Explained here: https://blog.devgenius.io/creating-stroked-labels-with-uikit-a-how-to-guide-7a024652e978
/// More info on the bug this works around: https://stackoverflow.com/questions/64318125/getting-issue-on-strokewidth-nsattributedstring-in-ios-14
class StrokedLabel: UILabel {
    override func drawText(in rect: CGRect) {
        guard let attributedText = attributedText?.mutableCopy() as? NSMutableAttributedString else {
            super.drawText(in: rect)
            return
        }

        attributedText.enumerateAttributes(in: NSRange(location: 0, length: attributedText.length), options: [], using: { attrs, range, _ in
            guard let strokeWidth = attrs[NSAttributedString.Key.strokeWidth] as? CGFloat else {
                return
            }

            attributedText.addAttributes([
                NSAttributedString.Key.strokeWidth: strokeWidth * 2
            ], range: range)
            self.attributedText = attributedText
            super.drawText(in: rect)

            let style = NSMutableParagraphStyle()
            style.alignment = textAlignment

            let attributes = [
                NSAttributedString.Key.strokeWidth: NSNumber(value: 0),
                NSAttributedString.Key.foregroundColor: textColor ?? UIColor.black,
                NSAttributedString.Key.font: font ?? UIFont.systemFont(ofSize: 17),
                NSAttributedString.Key.paragraphStyle: style
            ]

            attributedText.addAttributes(attributes, range: range)
            var textRect = boundingRect(
                with: attributedText,
                forCharacterRange: NSRange(location: 0, length: attributedText.length)
            )
            textRect.origin.y = (rect.size.height - textRect.size.height) / 2
            attributedText.draw(in: rect)
        })
    }

    private func boundingRect(
            with attributedString: NSAttributedString?,
            forCharacterRange range: NSRange
    ) -> CGRect {
        guard let attributedString = attributedString else {
            return .zero
        }
        let textStorage = NSTextStorage(attributedString: attributedString)
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)
        let textContainer = NSTextContainer(size: bounds.size)
        textContainer.lineFragmentPadding = 0
        layoutManager.addTextContainer(textContainer)

        var glyphRange = NSRange()
        layoutManager.characterRange(forGlyphRange: range, actualGlyphRange: &glyphRange)
        return layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
    }
}
