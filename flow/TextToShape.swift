//
//  TextToShape.swift
//  Text-Shape
//
//  Created by Balaji Venkatesh on 20/11/25.
//

//import SwiftUI
//import AppKit
//
///// Glass-Effect Text View
///// Fallsback to given color for older versions
//struct GlassEffectText: View {
//    var text: String
//    var font: NSFont
//    var fallbackColor: Color = .primary
//    var isClear: Bool = true
//    var glassTint: Color = .clear
//    var body: some View {
//        if #available(macOS 15, *) {
//            let textShape = TextToShape(value: text, font: font)
//            
//            Text(text)
//                .font(Font(font))
//                .opacity(0)
//                .glassEffect((isClear ? Glass.clear : Glass.regular).tint(glassTint), in: textShape)
//        } else {
//            Text(text)
//                .font(Font(font))
//                .foregroundStyle(fallbackColor)
//        }
//    }
//}
//
///// Text-To-Shape
//struct TextToShape: Shape {
//    var value: String
//    var font: NSFont
//    nonisolated func path(in rect: CGRect) -> Path {
//        var path = Path()
//        font.drawGlyphs(value) { position, glyphPath in
//            let transform = CGAffineTransform(translationX: position.x, y: position.y)
//                .scaledBy(x: 1, y: -1)
//            let newPath = Path(glyphPath).applying(transform)
//            /// Adding it to the main Path
//            path.addPath(newPath)
//        }
//        
//        /// Centering to the current bounds
//        let bounds = path.boundingRect
//        let offsetX = rect.midX - bounds.midX
//        let offsetY = rect.midY - bounds.midY
//        let centerTransform = CGAffineTransform(translationX: offsetX, y: offsetY)
//        
//        return path.applying(centerTransform)
//    }
//}
//
//extension NSFont {
//    nonisolated
//    /// Converting Font into a NSAttributedString with the given value
//    func toNSAttributedString(_ value: String) -> NSAttributedString {
//        return NSAttributedString(string: value, attributes: [.font: self])
//    }
//    
//    nonisolated
//    /// Return's Each Individual Glyph Path from the given text using the current font (Can be used to Draw Text as Path)
//    func drawGlyphs(_ value: String, draw: @escaping (_ position: CGPoint, _ glyphPath: CGPath) -> ()) {
//        let ctFont = self.ctFont
//        let attributedString = self.toNSAttributedString(value)
//        /// Extracting Lines & Runs from the Attributed String using CoreText APIs
//        let lines = CTLineCreateWithAttributedString(attributedString)
//        let runs = CTLineGetGlyphRuns(lines)
//        
//        for runIndex in 0..<CFArrayGetCount(runs) {
//            let run = unsafeBitCast(CFArrayGetValueAtIndex(runs, runIndex), to: CTRun.self)
//            let runCount = CTRunGetGlyphCount(run)
//            
//            /// Iterating Run and drawing Each Glyph
//            for index in 0..<runCount {
//                let range = CFRangeMake(index, 1)
//                var glyph = CGGlyph()
//                var position = CGPoint()
//                
//                /// Extracting Values
//                CTRunGetGlyphs(run, range, &glyph)
//                CTRunGetPositions(run, range, &position)
//                
//                if let glyphPath = CTFontCreatePathForGlyph(ctFont, glyph, nil) {
//                    /// Passing to draw!
//                    draw(position, glyphPath)
//                }
//            }
//        }
//    }
//}
//
//extension NSFont {
//    static func systemBold(ofSize size: CGFloat) -> NSFont {
//        return NSFont.systemFont(ofSize: size, weight: .bold)
//    }
//}

//#Preview {
//    ZStack {
////        Rectangle()
////            .foregroundStyle(.clear)
////            .overlay {
////                Image(.BG)
////                    .resizable()
////                    .aspectRatio(contentMode: .fill)
////            }
////            .ignoresSafeArea()
//        
//        GlassEffectText(text: "09:41", font: .systemBold(ofSize: 150))
//    }
//}

