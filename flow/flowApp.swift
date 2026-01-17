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

// MARK: - Display Mode (Shared)
enum LyricDisplayMode: String {
    case chunks = "Chunks"
    case fullLine = "Full Lines"
}

// MARK: - Shared State Manager
class DisplayModeManager: ObservableObject {
    static let shared = DisplayModeManager()
    @Published var displayMode: LyricDisplayMode = .chunks
    
    private init() {}
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var overlayWindow: OverlayWindow?
    var statusItem: NSStatusItem?
    var displayModeManager = DisplayModeManager.shared
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide dock icon
        NSApp.setActivationPolicy(.accessory)
        
        // Create menu bar item
        setupMenuBar()
        
        // Create and show overlay window with Spotify lyrics
        overlayWindow = OverlayWindow()
        overlayWindow?.makeKeyAndOrderFront(nil)
    }
    
    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "music.note", accessibilityDescription: "Lyrics")
        }
        
        let menu = NSMenu()
        
        // Display Mode submenu
        let displayModeItem = NSMenuItem(title: "Display Mode", action: nil, keyEquivalent: "")
        let displayModeSubmenu = NSMenu()
        
        let chunksItem = NSMenuItem(title: "Chunks", action: #selector(setChunksMode), keyEquivalent: "")
        chunksItem.target = self
        chunksItem.state = displayModeManager.displayMode == .chunks ? .on : .off
        
        let linesItem = NSMenuItem(title: "Full Lines", action: #selector(setFullLineMode), keyEquivalent: "")
        linesItem.target = self
        linesItem.state = displayModeManager.displayMode == .fullLine ? .on : .off
        
        displayModeSubmenu.addItem(chunksItem)
        displayModeSubmenu.addItem(linesItem)
        displayModeItem.submenu = displayModeSubmenu
        
        menu.addItem(displayModeItem)
        menu.addItem(NSMenuItem.separator())
        
        // Quit item
        let quitItem = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)
        
        statusItem?.menu = menu
    }
    
    @objc private func setChunksMode() {
        displayModeManager.displayMode = .chunks
        updateMenuCheckmarks()
    }
    
    @objc private func setFullLineMode() {
        displayModeManager.displayMode = .fullLine
        updateMenuCheckmarks()
    }
    
    private func updateMenuCheckmarks() {
        guard let menu = statusItem?.menu,
              let displayModeItem = menu.items.first,
              let submenu = displayModeItem.submenu else { return }
        
        for item in submenu.items {
            if item.title == "Chunks" {
                item.state = displayModeManager.displayMode == .chunks ? .on : .off
            } else if item.title == "Full Lines" {
                item.state = displayModeManager.displayMode == .fullLine ? .on : .off
            }
        }
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
    @ObservedObject private var displayModeManager = DisplayModeManager.shared
    
    @State private var chunks: [LyricChunk] = []
    @State private var currentChunk: LyricChunk?
    @State private var lines: [LyricLine] = []
    @State private var currentLine: LyricLine?
    @State private var fontSize: CGFloat = 100
    @State private var screenWidth: CGFloat = 0
    @State private var screenHeight: CGFloat = 0
    
    private let processor = LyricProcessor()
    private let horizontalPadding: CGFloat = 80
    private let verticalPadding: CGFloat = 80
    
    init() {
        let service = SpotifyService(spDc: APIconstants.sp_dc)
        _spotifyService = StateObject(wrappedValue: service)
        _playbackTracker = StateObject(wrappedValue: PlaybackTracker(spotifyService: service))
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if !authManager.isAuthenticated {
                    VStack(spacing: 15) {
                        Text("Connecting to Spotify")
                            .font(.system(size: 44, weight: .bold))
                            .foregroundColor(.white)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black.opacity(0.3))
                } else {
                    // Display based on current mode
                    if displayModeManager.displayMode == .chunks {
                        if let chunk = currentChunk {
                            GlassEffectText(
                                text: chunk.text + " ",
                                font: NSFont(name: "ROUND8-FOUR", size: fontSize * 1.7) ?? NSFont.systemFont(ofSize: fontSize)
                            )
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                        }
                    } else {
                        if let line = currentLine {
                            GlassEffectText(
                                text: line.words + " ",
                                font: NSFont(name: "ROUND8-FOUR", size: fontSize * 1.7) ?? NSFont.systemFont(ofSize: fontSize)
                            )
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                        }
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
                updateFontSize()
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
            updateCurrentDisplay(for: newValue)
        }
        .onChange(of: displayModeManager.displayMode) { oldValue, newValue in
            updateFontSize()
        }
        .onChange(of: currentChunk?.text) { oldValue, newValue in
            if displayModeManager.displayMode == .chunks {
                updateFontSize()
            }
        }
        .onChange(of: currentLine?.words) { oldValue, newValue in
            if displayModeManager.displayMode == .fullLine {
                updateFontSize()
            }
        }
        .onAppear {
            authManager.initiateLogin()
        }
        .onDisappear {
            playbackTracker.stopTracking()
        }
    }
    
    private func updateFontSize() {
        let text: String
        if displayModeManager.displayMode == .chunks {
            text = currentChunk?.text ?? ""
        } else {
            text = currentLine?.words ?? ""
        }
        
        guard !text.isEmpty, screenWidth > 0, screenHeight > 0 else {
            fontSize = 100
            return
        }
        
        updateFontSize(for: text, screenWidth: screenWidth, screenHeight: screenHeight)
    }
    
    private func updateFontSize(for text: String, screenWidth: CGFloat, screenHeight: CGFloat) {
        guard !text.isEmpty, screenWidth > 0, screenHeight > 0 else {
            fontSize = 100
            return
        }
        
        let availableWidth = screenWidth - (horizontalPadding * 2)
        let availableHeight = screenHeight - (verticalPadding * 2)
        
        let fontName = "ROUND8-FOUR"
        
        var minSize: CGFloat = 20
        var maxSize: CGFloat = 800
        var optimalSize: CGFloat = 100
        
        while maxSize - minSize > 1 {
            let testSize = (minSize + maxSize) / 2
            let testFont = NSFont(name: fontName, size: testSize * 1.7) ?? NSFont.systemFont(ofSize: testSize * 1.7)
            
            let textSize = measureTextSize(text: text, font: testFont)
            
            if textSize.width <= availableWidth && textSize.height <= availableHeight {
                optimalSize = testSize
                minSize = testSize
            } else {
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
            let fetchedLines = try await spotifyService.fetchLyrics(for: track.id)
            
            // Preprocess lines to remove punctuation
            let cleanedLines = fetchedLines.map { line in
                LyricLine(
                    startTimeMs: line.startTimeMs,
                    words: removePunctuation(from: line.words)
                )
            }
            
            let processedChunks = processor.process(lines: cleanedLines)
            
            await MainActor.run {
                chunks = processedChunks
                lines = cleanedLines
            }
        } catch {
            print("Error loading lyrics: \(error)")
        }
    }
    
    private func removePunctuation(from text: String) -> String {
        let allowedCharacters = CharacterSet.letters.union(.whitespaces)
        return text.components(separatedBy: allowedCharacters.inverted).joined()
    }
    
    private func updateCurrentDisplay(for time: Double) {
        if displayModeManager.displayMode == .chunks {
            let activeChunk = chunks.first { chunk in
                time >= chunk.startTime && time < chunk.endTime
            }
            
            if currentChunk?.id != activeChunk?.id {
                currentChunk = activeChunk
            }
        } else {
            let activeLine = lines.first { line in
                let lineEnd = getLineEndTime(for: line)
                return time >= line.startTime && time < lineEnd
            }
            
            if currentLine?.startTimeMs != activeLine?.startTimeMs {
                currentLine = activeLine
            }
        }
    }
    
    private func getLineEndTime(for line: LyricLine) -> Double {
        if let index = lines.firstIndex(where: { $0.startTimeMs == line.startTimeMs }),
           index < lines.count - 1 {
            return lines[index + 1].startTime
        }
        return line.startTime + 4000
    }
}

import SwiftUI
import AppKit

/// Glass-Effect Text View
struct GlassEffectText: View {
    var text: String
    var font: NSFont
    var fallbackColor: Color = .primary
    var isClear: Bool = true
    var glassTint: Color = .clear
    
    var body: some View {
        let textShape = TextToShape(value: text, font: font)
        
        ZStack {
            textShape
                .glassEffect((Glass.clear).tint(.clear), in: textShape)
                .colorInvert()
        }
        .compositingGroup()
        .opacity(0.5)
        .shadow(color: Color.black.opacity(0.3), radius: 5, x: 10, y: 15)
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
            path.addPath(newPath)
        }
        
        let bounds = path.boundingRect
        let offsetX = rect.midX - bounds.midX
        let offsetY = rect.midY - bounds.midY
        let centerTransform = CGAffineTransform(translationX: offsetX, y: offsetY)
        
        return path.applying(centerTransform)
    }
}

extension NSFont {
    var ctFont: CTFont {
        CTFontCreateWithName(self.fontName as CFString, self.pointSize, nil)
    }

    nonisolated
    func toNSAttributedString(_ value: String) -> NSAttributedString {
        return NSAttributedString(string: value, attributes: [.font: self])
    }
    
    nonisolated
    func drawGlyphs(_ value: String, draw: @escaping (_ position: CGPoint, _ glyphPath: CGPath) -> ()) {
        let ctFont = self.ctFont
        let attributedString = self.toNSAttributedString(value)
        let lines = CTLineCreateWithAttributedString(attributedString)
        let runs = CTLineGetGlyphRuns(lines)
        
        for runIndex in 0..<CFArrayGetCount(runs) {
            let run = unsafeBitCast(CFArrayGetValueAtIndex(runs, runIndex), to: CTRun.self)
            let runCount = CTRunGetGlyphCount(run)
            
            for index in 0..<runCount {
                let range = CFRangeMake(index, 1)
                var glyph = CGGlyph()
                var position = CGPoint()
                
                CTRunGetGlyphs(run, range, &glyph)
                CTRunGetPositions(run, range, &position)
                
                if let glyphPath = CTFontCreatePathForGlyph(ctFont, glyph, nil) {
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
