//
//  flowApp.swift
//  flow
//
//  Created by Drew Visconti on 11/29/25.
//

import SwiftUI
import AppKit


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
        ZStack {
            // Semi-transparent background
            Color.gray.opacity(0)
            
            Text(displayText + " ")
                .font(.custom("Fastup-Regular", size: fontSize))
                .opacity(0.6)
//                .glassEffect()
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

//#Preview {
//    ContentView()
//        .frame(width: 800, height: 600)
//}

