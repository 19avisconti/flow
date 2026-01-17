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
        
        // Create and show overlay window with Spotify lyrics
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
        
        // Set content view to Spotify lyric overlay
        self.contentView = NSHostingView(rootView: SpotifyOverlayView())
    }
}

struct SpotifyOverlayView: View {
    @StateObject private var authManager = SpotifyAuthManager()
    @StateObject private var spotifyService: SpotifyService
    @StateObject private var playbackTracker: PlaybackTracker
    
    @State private var chunks: [LyricChunk] = []
    @State private var currentChunk: LyricChunk?
    @State private var fontSize: CGFloat = 100
    @State private var screenWidth: CGFloat = 0
    @State private var screenHeight: CGFloat = 0
    
    private let processor = LyricProcessor()
    private let horizontalPadding: CGFloat = 80 // Padding on left/right
    private let verticalPadding: CGFloat = 80   // Padding on top/bottom
    
    init() {
        let service = SpotifyService(spDc: APIconstants.sp_dc)
        _spotifyService = StateObject(wrappedValue: service)
        _playbackTracker = StateObject(wrappedValue: PlaybackTracker(spotifyService: service))
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if !authManager.isAuthenticated {
                    // Show login prompt (semi-transparent)
                    VStack(spacing: 15) {
                        Text("Connecting to Spotify")
                            .font(.system(size: 44, weight: .bold))
                            .foregroundColor(.white)
                        
//                        Button("Login with Spotify") {
//                            authManager.initiateLogin()
//                        }
//                        .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black.opacity(0.3))
                } else {
                    // Show current lyric chunk with glass effect
                    if let chunk = currentChunk {
                        GlassEffectText(
                            text: chunk.text + " ",
                            font: NSFont(name: "ROUND8-FOUR", size: fontSize * 1.7) ?? NSFont.systemFont(ofSize: fontSize)
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                        // Removed .transition(.opacity) - no more animation!
                    }
                }
            }
            .onAppear {
                screenWidth = geometry.size.width
                screenHeight = geometry.size.height
            }
            .onChange(of: geometry.size) { oldValue, newValue in
                screenWidth = newValue.width
                screenHeight = newValue.height
                if let chunk = currentChunk {
                    updateFontSize(for: chunk.text, screenWidth: screenWidth, screenHeight: screenHeight)
                }
            }
        }
        .onChange(of: authManager.accessToken) { oldValue, newValue in
            if let token = newValue {
                spotifyService.setAccessToken(token)
                playbackTracker.startTracking()
                
                Task {
                    await loadCurrentTrackLyrics()
                }
            }
        }
        .onChange(of: spotifyService.currentTrack?.id) { oldValue, newValue in
            if newValue != nil {
                Task {
                    await loadCurrentTrackLyrics()
                }
            }
        }
        .onChange(of: playbackTracker.currentTime) { oldValue, newValue in
            updateCurrentChunk(for: newValue)
        }
        .onChange(of: currentChunk?.text) { oldValue, newValue in
            if let text = newValue {
                updateFontSize(for: text, screenWidth: screenWidth, screenHeight: screenHeight)
            }
        }
        .onAppear {
            authManager.initiateLogin()
        }
        .onDisappear {
            playbackTracker.stopTracking()
        }
    }
    
    private func updateFontSize(for text: String, screenWidth: CGFloat, screenHeight: CGFloat) {
        guard !text.isEmpty, screenWidth > 0, screenHeight > 0 else {
            fontSize = 100
            return
        }
        
        // Available width and height for text
        let availableWidth = screenWidth - (horizontalPadding * 2)
        let availableHeight = screenHeight - (verticalPadding * 2)
        
        // Get the font to use
        let fontName = "ROUND8-FOUR"
        
        // Binary search for optimal font size
        var minSize: CGFloat = 20
        var maxSize: CGFloat = 800
        var optimalSize: CGFloat = 100
        
        // Binary search with precision of 1 point
        while maxSize - minSize > 1 {
            let testSize = (minSize + maxSize) / 2
            let testFont = NSFont(name: fontName, size: testSize * 1.7) ?? NSFont.systemFont(ofSize: testSize * 1.7)
            
            let textSize = measureTextSize(text: text, font: testFont)
            
            // Check if text fits both width AND height constraints
            if textSize.width <= availableWidth && textSize.height <= availableHeight {
                // Text fits, try larger
                optimalSize = testSize
                minSize = testSize
            } else {
                // Text too big, try smaller
                maxSize = testSize
            }
        }
        
        self.fontSize = optimalSize
    }
    
    private func measureTextSize(text: String, font: NSFont) -> CGSize {
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let size = (text as NSString).size(withAttributes: attributes)
        return size
    }
    
    private func loadCurrentTrackLyrics() async {
        guard let track = spotifyService.currentTrack else { return }
        
        do {
            let lines = try await spotifyService.fetchLyrics(for: track.id)
            
            // Preprocess lines to remove punctuation
            let cleanedLines = lines.map { line in
                LyricLine(
                    startTimeMs: line.startTimeMs,
                    words: removePunctuation(from: line.words)
                )
            }
            
            let processedChunks = processor.process(lines: cleanedLines)
            
            await MainActor.run {
                chunks = processedChunks
            }
        } catch {
            print("Error loading lyrics: \(error)")
        }
    }
    
    private func removePunctuation(from text: String) -> String {
        // Remove all punctuation characters but keep spaces and letters
        let allowedCharacters = CharacterSet.letters.union(.whitespaces)
        return text.components(separatedBy: allowedCharacters.inverted).joined()
    }
    
    private func updateCurrentChunk(for time: Double) {
        let active = chunks.first { chunk in
            time >= chunk.startTime && time < chunk.endTime
        }
        
        // Direct assignment without animation
        if currentChunk?.id != active?.id {
            currentChunk = active
        }
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
            .glassEffect((Glass.clear).tint(.clear), in: textShape)
            .colorInvert()
            .shadow(color: Color.black.opacity(0.5), radius: 5, x: 10, y: 15)
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

