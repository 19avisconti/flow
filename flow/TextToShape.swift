import SwiftUI
import AppKit
import CoreText

extension NSFont {
    var ctFont: CTFont { CTFontCreateWithName(self.fontName as CFString, self.pointSize, nil) }

    func textSize(_ value: String) -> CGSize {
        (value as NSString).size(withAttributes: [.font: self])
    }

    func path(for value: String) -> CGPath {
        let attr = NSMutableAttributedString(string: value)
        let range = NSRange(location: 0, length: attr.length)
        attr.addAttribute(NSAttributedString.Key(kCTFontAttributeName as String), value: ctFont, range: range)

        let line = CTLineCreateWithAttributedString(attr)
        let runs = CTLineGetGlyphRuns(line) as NSArray
        let combined = CGMutablePath()

        for case let run as CTRun in runs {
            let glyphCount = CTRunGetGlyphCount(run)
            if glyphCount == 0 { continue }

            var glyphs = Array(repeating: CGGlyph(), count: glyphCount)
            var positions = Array(repeating: CGPoint.zero, count: glyphCount)

            CTRunGetGlyphs(run, CFRangeMake(0, 0), &glyphs)
            CTRunGetPositions(run, CFRangeMake(0, 0), &positions)

            for i in 0..<glyphCount {
                if let glyphPath = CTFontCreatePathForGlyph(ctFont, glyphs[i], nil) {
                    var t = CGAffineTransform(translationX: positions[i].x, y: positions[i].y)
                    combined.addPath(glyphPath, transform: t)
                }
            }
        }

        return combined
    }
}

public struct TextShape: Shape {
    public let text: String
    public let font: NSFont

    public init(text: String, font: NSFont) {
        self.text = text
        self.font = font
    }

    public func path(in rect: CGRect) -> Path {
        let raw = font.path(for: text)
        let size = font.textSize(text)

        let scale = min(rect.width / max(size.width, 1e-6), rect.height / max(size.height, 1e-6))
        let scaledSize = CGSize(width: size.width * scale, height: size.height * scale)

        // Center horizontally, and place baseline so text reads upright in SwiftUI (flip Y)
        var t = CGAffineTransform(translationX: rect.minX + (rect.width - scaledSize.width) / 2,
                                  y: rect.minY + (rect.height + scaledSize.height) / 2)
        t = t.scaledBy(x: scale, y: -scale)

        let final = raw.copy(using: &t) ?? raw
        return Path(final)
    }
}

@inlinable
public func TextToShape(_ text: String, font: NSFont) -> TextShape {
    TextShape(text: text, font: font)
}
