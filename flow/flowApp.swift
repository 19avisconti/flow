//
//  flowApp.swift
//  flow
//
//  Created by Drew Visconti on 11/29/25.
//

import SwiftUI
import AppKit
import CoreText

@main
struct SubtitleOverlayApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var overlayWindow: OverlayWindow?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide dock icon
        NSApp.setActivationPolicy(.accessory)
        
        // Create and show overlay window
        overlayWindow = OverlayWindow()
        overlayWindow?.makeKeyAndOrderFront(nil)
    }
}

class OverlayWindow: NSWindow {
    init() {
        guard let screen = NSScreen.main else {
            super.init(
                contentRect: .zero,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            return
        }
        
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        
        // Window configuration
        self.level = .statusBar
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        self.isOpaque = false
        self.hasShadow = false
        self.ignoresMouseEvents = true
        self.backgroundColor = .clear
        self.isReleasedWhenClosed = false
        
        // Set content view
        self.contentView = NSHostingView(rootView: ContentView())
    }
}

struct ContentView: View {
    @State private var displayText = ""
    @State private var fontSize: CGFloat = 100
    @State private var timer: Timer?
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
//                let nsFont = NSFont(name: "Fastup-Regular", size: fontSize) ?? NSFont.systemFont(ofSize: fontSize)
                
                
                GlassEffectText(text: displayText + " ", font: .systemBold(ofSize: fontSize))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                
//                Rectangle()
//                    .fill(.clear)
//                    .frame(width: geometry.size.width, height: geometry.size.height)
//                    .glassEffect(
//                        .regular,
//                        in: TextShape(text: displayText + " ", font: nsFont)
//                    )
            }
        }
        .onAppear {
            startUpdating()
        }
        .onDisappear {
            timer?.invalidate()
        }
    }
    
    func startUpdating() {
        updateText()
    }
    
    func updateText() {
        // Generate new text
        displayText = generateRandomString()
        
        // Calculate font size based on text length
        let baseSize: CGFloat = 500
        let reduction: CGFloat = CGFloat(displayText.count) * 25
        fontSize = max(50, baseSize - reduction) // Minimum font size of 50
        
        // Schedule next update
        let delay = Double.random(in: 0.1...0.5)
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { _ in
            updateText()
        }
    }
    
    func generateRandomString() -> String {
        let length = Int.random(in: 3...5)
        let characters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%"
        return String((0..<length).map { _ in characters.randomElement()! })
    }
}

import SwiftUI
import AppKit

/// Glass-Effect Text View
/// Fallsback to given color for older versions
struct GlassEffectText: View {
    var text: String
    var font: NSFont
    var fallbackColor: Color = .primary
    var isClear: Bool = true
    var glassTint: Color = .clear
    var body: some View {
        let textShape = TextToShape(value: text, font: font)
        
        Text(text)
            .font(Font(font))
            .opacity(0)
            .glassEffect((isClear ? Glass.clear : Glass.regular).tint(glassTint), in: textShape)
    }
}

/// Text-To-Shape
struct TextToShape: Shape {
    var value: String
    var font: NSFont
    nonisolated func path(in rect: CGRect) -> Path {
        var path = Path()
        font.drawGlyphs(value) { position, glyphPath in
            let transform = CGAffineTransform(translationX: position.x, y: position.y)
                .scaledBy(x: 1, y: -1)
            let newPath = Path(glyphPath).applying(transform)
            /// Adding it to the main Path
            path.addPath(newPath)
        }
        
        /// Centering to the current bounds
        let bounds = path.boundingRect
        let offsetX = rect.midX - bounds.midX
        let offsetY = rect.midY - bounds.midY
        let centerTransform = CGAffineTransform(translationX: offsetX, y: offsetY)
        
        return path.applying(centerTransform)
    }
}

extension NSFont {
    /// Bridge NSFont to CTFont for CoreText APIs
    var ctFont: CTFont {
        CTFontCreateWithName(self.fontName as CFString, self.pointSize, nil)
    }

    nonisolated
    /// Converting Font into a NSAttributedString with the given value
    func toNSAttributedString(_ value: String) -> NSAttributedString {
        return NSAttributedString(string: value, attributes: [.font: self])
    }
    
    nonisolated
    /// Return's Each Individual Glyph Path from the given text using the current font (Can be used to Draw Text as Path)
    func drawGlyphs(_ value: String, draw: @escaping (_ position: CGPoint, _ glyphPath: CGPath) -> ()) {
        let ctFont = self.ctFont
        let attributedString = self.toNSAttributedString(value)
        /// Extracting Lines & Runs from the Attributed String using CoreText APIs
        let lines = CTLineCreateWithAttributedString(attributedString)
        let runs = CTLineGetGlyphRuns(lines)
        
        for runIndex in 0..<CFArrayGetCount(runs) {
            let run = unsafeBitCast(CFArrayGetValueAtIndex(runs, runIndex), to: CTRun.self)
            let runCount = CTRunGetGlyphCount(run)
            
            /// Iterating Run and drawing Each Glyph
            for index in 0..<runCount {
                let range = CFRangeMake(index, 1)
                var glyph = CGGlyph()
                var position = CGPoint()
                
                /// Extracting Values
                CTRunGetGlyphs(run, range, &glyph)
                CTRunGetPositions(run, range, &position)
                
                if let glyphPath = CTFontCreatePathForGlyph(ctFont, glyph, nil) {
                    /// Passing to draw!
                    draw(position, glyphPath)
                }
            }
        }
    }
}

extension NSFont {
    static func systemBold(ofSize size: CGFloat) -> NSFont {
        return NSFont.systemFont(ofSize: size, weight: .bold)
    }
}

