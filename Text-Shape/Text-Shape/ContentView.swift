//
//  ContentView.swift
//  Text-Shape
//
//  Created by Balaji Venkatesh on 20/11/25.
//

import SwiftUI

/// Background Image:
/// Photo by Max Andrey: https://www.pexels.com/photo/sunflower-selective-focus-photography-1366630/

struct ContentView: View {
    var body: some View {
        NavigationStack {
            List {
                NavigationLink("Glass Effect") {
                    Example1()
                }
                
                NavigationLink("Writing Effect") {
                    Example2()
                }
            }
            .navigationTitle("Text To Shape")
        }
    }
}

struct Example1: View {
    @State private var progressSlider: CGFloat = 0
    @State private var lastStoredValue: CGFloat = 0
    var body: some View {
        ZStack {
            /// Rounded Border Shape
            let backgroundShape = RoundedRectangle(cornerRadius: 15)
                .stroke(lineWidth: 3)
            /// Grabber Shape
            let grabberShape = Circle()
                .trim(from: 0.28, to: 0.5)
                .stroke(style: .init(lineWidth: 18, lineCap: .round, lineJoin: .round))
            
            Rectangle()
                .foregroundStyle(.clear)
                .overlay {
                    Image(.BG)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                }
                .ignoresSafeArea()
            
            /// Drawing Text
            GlassEffectText(text: "09:41", font: .systemFont(ofSize: 100 + progressSlider, weight: .semibold, width: .compressed), fallbackColor: .white)
                .frame(maxWidth: .infinity)
                .overlay {
                    ZStack {
                        /// Drawing Background Border
                        Group {
                            if #available(iOS 26, *) {
                                backgroundShape
                                    .fill(.clear)
                                    .glassEffect(.clear, in: backgroundShape)
                            } else {
                                backgroundShape
                                    .fill(.white)
                            }
                        }
                        
                        /// Drawing Grabber Shape
                        Group {
                            if #available(iOS 26, *) {
                                grabberShape
                                    .fill(.clear)
                                    .glassEffect(.clear, in: grabberShape)
                            } else {
                                grabberShape
                                    .fill(.white)
                            }
                        }
                        .frame(width: 50, height: 50)
                        .contentShape(.rect)
                        .scaleEffect(x: -1)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                        .gesture(dragGesture)
                    }
                }
                .padding(.horizontal, 15)
                .padding(.top, 10)
                .frame(maxHeight: .infinity, alignment: .top)
        }
    }
    
    var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                progressSlider = max(min(value.translation.height + lastStoredValue, 115), 0)
            }.onEnded { value in
                lastStoredValue = progressSlider
            }
    }
}

struct Example2: View {
    @State private var animate: Bool = false
    @State private var changeText: Bool = false
    var body: some View {
        List {
            let textShape = TextToShape(value: !changeText ? "Hello World!" : "09:41", font: textFont)
            
            Section("Demo") {
                textShape
                    .trim(from: 0, to: animate ? 1 : 0)
                    .stroke(lineWidth: 4)
                    .frame(height: 100)
            }
            
            Button("Animate Text") {
                withAnimation(.easeInOut(duration: 4), completionCriteria: .logicallyComplete) {
                    animate.toggle()
                } completion: {
                    guard !changeText else {
                        changeText = animate
                        return
                    }
                    changeText = !animate
                }
            }
        }
        .navigationTitle("Writing Effect")
    }
    
    var textFont: UIFont {
        /// Native Font which is somewhat similar to hand writing!
        if let customFont = UIFont(name: "Bradley Hand", size: 60) {
            return customFont
        }
        
        return .systemFont(ofSize: 40, weight: .bold)
    }
}

#Preview {
    ContentView()
}
