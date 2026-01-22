//
//  lyrics.swift
//  flow
//
//  Created by Drew Visconti on 1/14/26.
//

import SwiftUI
import Foundation
import Network
import CryptoKit

// MARK: - Data Models

struct SpotifyLyricResponse: Codable {
    let lyrics: LyricData
}

struct LyricData: Codable {
    let lines: [LyricLine]
}

struct LyricLine: Codable {
    let startTimeMs: String
    let words: String
    
    var startTime: Double { Double(startTimeMs) ?? 0 }
}

// Added to track internal token state
struct InternalToken {
    let accessToken: String
    let expirationURL: Int64
}

// MARK: - Error Handling

enum SpotifyError: Error {
    case spDcNotSet
    case tokenRequestFailed(String)
    case invalidSpDc
    case general(String)
}

// ... (WordTiming, LyricChunk, SpotifyCurrentlyPlaying, SpotifyTrack, SpotifyArtist, SpotifyAuthResponse remain the same)

struct WordTiming {
    let word: String
    let startTime: Double
    let endTime: Double
}

struct LyricChunk: Identifiable {
    let id = UUID()
    let text: String
    let startTime: Double
    let endTime: Double
}

struct SpotifyCurrentlyPlaying: Codable {
    let item: SpotifyTrack?
    let progress_ms: Int?
    let is_playing: Bool
}

struct SpotifyTrack: Codable {
    let id: String
    let name: String
    let artists: [SpotifyArtist]
    let duration_ms: Int
}

struct SpotifyArtist: Codable {
    let name: String
}

struct SpotifyAuthResponse: Codable {
    let access_token: String
    let refresh_token: String?
    let expires_in: Int
}

// MARK: - Local Callback Server
class LocalCallbackServer {
    private var listener: NWListener?
    private let port: UInt16
    private let onCodeReceived: (String) -> Void
    
    init(port: UInt16, onCodeReceived: @escaping (String) -> Void) {
        self.port = port
        self.onCodeReceived = onCodeReceived
    }
    
    func start() {
        do {
            let params = NWParameters.tcp
            let host = NWEndpoint.Host("127.0.0.1")
            let port = NWEndpoint.Port(integerLiteral: self.port)
            listener = try NWListener(using: params, on: port)
            listener?.newConnectionHandler = { [weak self] connection in
                self?.handleConnection(connection)
            }
            listener?.start(queue: .main)
        } catch {
            print("Failed to start server: \(error)")
        }
    }
    
    func stop() {
        listener?.cancel()
        listener = nil
    }
    
    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: .main)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let data = data, let request = String(data: data, encoding: .utf8) else { return }
            if let code = self?.extractCode(from: request) {
                let response = "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\n\r\n<html><body><h1>Success!</h1><script>window.close();</script></body></html>"
                connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
                    connection.cancel()
                })
                self?.onCodeReceived(code)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self?.stop() }
            }
        }
    }
    
    private func extractCode(from request: String) -> String? {
        let parts = request.components(separatedBy: " ")
        guard parts.count >= 2 else { return nil }
        let path = parts[1]
        guard let url = URLComponents(string: "http://127.0.0.1:3000\(path)") else { return nil }
        return url.queryItems?.first(where: { $0.name == "code" })?.value
    }
}

// MARK: - Spotify Authentication Manager
class SpotifyAuthManager: ObservableObject {
    @Published var isAuthenticated = false
    @Published var accessToken: String?
    
    private let clientID = APIconstants.clientID
    private let clientSecret = APIconstants.clientSecret
    private let redirectUri = APIconstants.redirectURI
    private let scopes = "user-read-playback-state user-read-currently-playing"
    private var localServer: LocalCallbackServer?
    
    func initiateLogin() {
        localServer = LocalCallbackServer(port: 3000) { [weak self] code in
            Task { await self?.handleCallback(code: code) }
        }
        localServer?.start()
        
        let authURL = "https://accounts.spotify.com/authorize?" +
            "client_id=\(clientID)" +
            "&response_type=code" +
            "&redirect_uri=\(redirectUri)" +
            "&scope=\(scopes.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
        
        if let url = URL(string: authURL) {
            NSWorkspace.shared.open(url)
        }
    }
    
    func handleCallback(code: String) async {
        do {
            let token = try await exchangeCodeForToken(code: code)
            await MainActor.run {
                self.accessToken = token
                self.isAuthenticated = true
            }
        } catch {
            print("Auth error: \(error)")
        }
    }
    
    private func exchangeCodeForToken(code: String) async throws -> String {
        let url = URL(string: "https://accounts.spotify.com/api/token")!
        let authString = "\(clientID):\(clientSecret)"
        let base64Auth = authString.data(using: .utf8)?.base64EncodedString() ?? ""
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Basic \(base64Auth)", forHTTPHeaderField: "Authorization")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "redirect_uri", value: redirectUri),
            URLQueryItem(name: "grant_type", value: "authorization_code")
        ]
        request.httpBody = components.query?.data(using: .utf8)
        
        let (data, _) = try await URLSession.shared.data(for: request)
        let tokenResponse = try JSONDecoder().decode(SpotifyAuthResponse.self, from: data)
        return tokenResponse.access_token
    }
}

// MARK: - Spotify API Service

class SpotifyService: ObservableObject {
    @Published var currentTrack: SpotifyTrack?
    @Published var progressMs: Double = 0
    @Published var isPlaying: Bool = false
    
    let spDc: String
    private var accessToken: String? // This is the OAuth user token
    
    // URLs for token management
    private let tokenURL = "https://open.spotify.com/api/token"
    private let serverTimeURL = "https://open.spotify.com/api/server-time"
    private let secretKeyURL = "https://github.com/xyloflake/spot-secrets-go/blob/main/secrets/secretDict.json?raw=true"
    private let lyricsURL = "https://spclient.wg.spotify.com/color-lyrics/v2/track/"
    
    // Cache file for storing token data
    private var cacheFile: URL {
        let tempDir = FileManager.default.temporaryDirectory
        return tempDir.appendingPathComponent("spotify_token.json")
    }
    
    init(spDc: String) {
        self.spDc = spDc
    }
    
    func setAccessToken(_ token: String) {
        self.accessToken = token
    }
    
    func fetchCurrentlyPlaying() async throws -> SpotifyTrack? {
        guard let token = accessToken else { return nil }
        
        let url = URL(string: "https://api.spotify.com/v1/me/player/currently-playing")!
        var request = URLRequest(url: url)
        request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 204 { return nil }
        
        let currentlyPlaying = try JSONDecoder().decode(SpotifyCurrentlyPlaying.self, from: data)
        await MainActor.run {
            self.currentTrack = currentlyPlaying.item
            self.progressMs = Double(currentlyPlaying.progress_ms ?? 0)
            self.isPlaying = currentlyPlaying.is_playing
        }
        return currentlyPlaying.item
    }
    
    // MARK: - Lyrics Fetching
    
    /// Main function to fetch lyrics for a track
    /// Checks token expiration, gets valid token, then fetches lyrics
    func fetchLyrics(for trackId: String) async throws -> [LyricLine] {
        // Check if token is expired and refresh if needed
        try await checkTokenExpire()
        
        // Read token from cache
        let data = try Data(contentsOf: cacheFile)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = json["accessToken"] as? String else {
            throw SpotifyError.general("Failed to read token from cache")
        }
        
        
        // Request lyrics
        let urlString = "\(lyricsURL)\(trackId)?format=json&market=from_token"
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }
        
        var request = URLRequest(url: url)
        request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.addValue("WebPlayer", forHTTPHeaderField: "App-platform")
        request.addValue("Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/101.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        
        let (responseData, urlResponse) = try await URLSession.shared.data(for: request)
        
        // Check response
        if let http = urlResponse as? HTTPURLResponse {
            
            if http.statusCode == 429 {
                throw SpotifyError.general("Rate limited by Spotify")
            } else if http.statusCode == 404 {
                throw SpotifyError.general("Lyrics not found")
            } else if http.statusCode >= 400 {
                let errorText = String(data: responseData, encoding: .utf8) ?? "Unknown error"
                throw SpotifyError.general("Spotify API error \(http.statusCode): \(errorText)")
            }
        }
        
        let result = try JSONDecoder().decode(SpotifyLyricResponse.self, from: responseData)
        return result.lyrics.lines
    }
    
    // MARK: - Token Management
    
    /// Checks if the cached token has expired and fetches a new one if needed
    private func checkTokenExpire() async throws {
        let fileExists = FileManager.default.fileExists(atPath: cacheFile.path)
        var timeLeft: Int64 = 0
        let timeNow = Int64(Date().timeIntervalSince1970 * 1000)
        
        var shouldGetNewToken = !fileExists
        
        if fileExists {
            do {
                let data = try Data(contentsOf: cacheFile)
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let expirationTime = json["accessTokenExpirationTimestampMs"] as? Int64 {
                    timeLeft = expirationTime
                } else {
                    shouldGetNewToken = true
                }
            } catch {
                shouldGetNewToken = true
            }
        }
        
        if shouldGetNewToken || timeLeft < timeNow {
            try await getToken()
        }
    }
    
    /// Requests a new access token from Spotify using the sp_dc cookie
    private func getToken() async throws {
        guard !spDc.isEmpty else {
            throw SpotifyError.spDcNotSet
        }
        
        // Get server time params (includes TOTP)
        let params = try await getServerTimeParams()
        
        // Build URL with query parameters
        var urlComponents = URLComponents(string: tokenURL)
        urlComponents?.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
        
        guard let url = urlComponents?.url else {
            throw SpotifyError.general("Invalid URL")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        request.setValue("sp_dc=\(spDc)", forHTTPHeaderField: "Cookie")
        
        let (responseData, urlResponse) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = urlResponse as? HTTPURLResponse else {
            throw SpotifyError.general("Invalid response")
        }
        
        
        guard httpResponse.statusCode == 200 else {
            let errorText = String(data: responseData, encoding: .utf8) ?? "Unknown error"
            throw SpotifyError.tokenRequestFailed("Token request failed (\(httpResponse.statusCode)): \(errorText)")
        }
        
        // Parse JSON
        guard let tokenJson = try JSONSerialization.jsonObject(with: responseData) as? [String: Any] else {
            throw SpotifyError.general("Failed to parse JSON")
        }
        
        // Check if anonymous
        if let isAnonymous = tokenJson["isAnonymous"] as? Bool, isAnonymous {
            throw SpotifyError.invalidSpDc
        }
        
        
        // Save to cache file
        try responseData.write(to: cacheFile)
    }
    
    /// Fetches server time and generates TOTP parameters for authentication
    private func getServerTimeParams() async throws -> [String: String] {
        // Get server time
        guard let url = URL(string: serverTimeURL) else {
            throw SpotifyError.general("Invalid server time URL")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        let (responseData, urlResponse) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = urlResponse as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw SpotifyError.general("Failed to fetch server time")
        }
        
        // Parse server time JSON
        guard let serverTimeData = try JSONSerialization.jsonObject(with: responseData) as? [String: Any],
              let serverTimeSeconds = serverTimeData["serverTime"] as? Int else {
            throw SpotifyError.general("Failed to parse server time")
        }
        
        
        // Get secret key and version
        let (secret, version) = try await getLatestSecretKeyVersion()
        
        // Generate TOTP
        let totp = try generateTOTP(serverTime: serverTimeSeconds, secret: secret)
        
        
        // Get current timestamp
        let timestamp = Int(Date().timeIntervalSince1970)
        
        return [
            "reason": "transport",
            "productType": "web-player",
            "totp": totp,
            "totpVer": version,
            "ts": String(timestamp)
        ]
    }
    
    /// Fetches the latest secret key from GitHub and transforms it
    /// The secret is XOR'd with ((index % 33) + 9) for each byte
    private func getLatestSecretKeyVersion() async throws -> (secret: Data, version: String) {
        guard let url = URL(string: secretKeyURL) else {
            throw SpotifyError.general("Invalid secret key URL")
        }
        
        let request = URLRequest(url: url)
        let (responseData, urlResponse) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = urlResponse as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw SpotifyError.general("Failed to fetch secrets")
        }
        
        // Parse JSON
        guard let secretsData = try JSONSerialization.jsonObject(with: responseData) as? [String: Any] else {
            throw SpotifyError.general("Failed to parse secrets JSON")
        }
        
        // Get the latest version (last key)
        let sortedKeys = secretsData.keys.sorted()
        guard let version = sortedKeys.last,
              let originalSecret = secretsData[version] as? [Int] else {
            throw SpotifyError.general("No secrets found")
        }
        
        
        // Transform the secret: XOR each value with ((index % 33) + 9)
        var transformed: [String] = []
        for (i, char) in originalSecret.enumerated() {
            let val = char ^ ((i % 33) + 9)
            transformed.append(String(val))
        }
        
        let transformedString = transformed.joined()
        guard let secretData = transformedString.data(using: .utf8) else {
            throw SpotifyError.general("Failed to convert secret to data")
        }
        
        return (secret: secretData, version: version)
    }
    
    /// Generates a Time-based One-Time Password (TOTP) using HMAC-SHA1
    /// Period: 30 seconds, Digits: 6
    private func generateTOTP(serverTime: Int, secret: Data) throws -> String {
        let period = 30
        let digits = 6
        
        // Calculate counter (time in 30-second intervals)
        let counter = UInt64(serverTime / period)
        
        // Convert counter to big-endian bytes
        var counterBytes = counter.bigEndian
        let counterData = Data(bytes: &counterBytes, count: MemoryLayout<UInt64>.size)
        
        // Compute HMAC-SHA1
        let key = SymmetricKey(data: secret)
        let hmac = HMAC<Insecure.SHA1>.authenticationCode(for: counterData, using: key)
        let hmacData = Data(hmac)
        
        // Dynamic truncation (RFC 4226)
        let offset = Int(hmacData[hmacData.count - 1] & 0x0F)
        
        // Extract 4 bytes starting at offset
        let byte1 = UInt32(hmacData[offset] & 0x7F)
        let byte2 = UInt32(hmacData[offset + 1] & 0xFF)
        let byte3 = UInt32(hmacData[offset + 2] & 0xFF)
        let byte4 = UInt32(hmacData[offset + 3] & 0xFF)
        
        // Combine bytes into 32-bit integer
        let binary = (byte1 << 24) | (byte2 << 16) | (byte3 << 8) | byte4
        
        // Apply modulo
        let code = binary % UInt32(pow(10, Double(digits)))
        
        // Format as 6-digit string with leading zeros
        return String(format: "%0\(digits)d", code)
    }
}

// MARK: - Lyric Processor

class LyricProcessor {
    let chunkCharLimit = 15
    let gapThresholdMs = 400.0
    
    func process(lines: [LyricLine]) -> [LyricChunk] {
        var allChunks: [LyricChunk] = []
        
        for (index, line) in lines.enumerated() {
            let lineEnd = (index < lines.count - 1)
                ? lines[index + 1].startTime
                : line.startTime + 4000
            
            let timedWords = interpolate(line: line.words, start: line.startTime, end: lineEnd)
            let lineChunks = groupIntoChunks(words: timedWords)
            allChunks.append(contentsOf: lineChunks)
        }
        
        return allChunks
    }
    
    private func interpolate(line: String, start: Double, end: Double) -> [WordTiming] {
        let words = line.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        guard !words.isEmpty else { return [] }
        
        let duration = end - start
        let wordDur = duration / Double(words.count)
        
        return words.enumerated().map { i, text in
            WordTiming(
                word: text,
                startTime: start + (Double(i) * wordDur),
                endTime: start + (Double(i + 1) * wordDur)
            )
        }
    }
    
    private func groupIntoChunks(words: [WordTiming]) -> [LyricChunk] {
        var chunks: [LyricChunk] = []
        var currentWords: [WordTiming] = []
        var currentLen = 0
        
        for i in 0..<words.count {
            let word = words[i]
            let wordLen = word.word.count
            
            let isGap = i > 0 && (word.startTime - words[i-1].endTime > gapThresholdMs)
            
            if !currentWords.isEmpty && (currentLen + wordLen > chunkCharLimit || isGap) {
                chunks.append(finalizeChunk(currentWords))
                currentWords = []
                currentLen = 0
            }
            
            currentWords.append(word)
            currentLen += wordLen
        }
        
        if !currentWords.isEmpty {
            chunks.append(finalizeChunk(currentWords))
        }
        
        return chunks
    }
    
    private func finalizeChunk(_ words: [WordTiming]) -> LyricChunk {
        LyricChunk(
            text: words.map { $0.word }.joined(separator: " "),
            startTime: words.first!.startTime,
            endTime: words.last!.endTime
        )
    }
}

// MARK: - Playback Tracker

class PlaybackTracker: ObservableObject {
    @Published var currentTime: Double = 0
    
    private var timer: Timer?
    private let spotifyService: SpotifyService
    
    init(spotifyService: SpotifyService) {
        self.spotifyService = spotifyService
    }
    
    func startTracking() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task {
                try? await self?.updatePlaybackState()
            }
        }
    }
    
    func stopTracking() {
        timer?.invalidate()
        timer = nil
    }
    
    private func updatePlaybackState() async throws {
        _ = try await spotifyService.fetchCurrentlyPlaying()
        
        await MainActor.run {
            self.currentTime = spotifyService.progressMs
        }
    }
    
    deinit {
        timer?.invalidate()
    }
}

// MARK: - Main Lyric Display View

struct LyricDisplayView: View {
    @StateObject private var authManager = SpotifyAuthManager()
    @StateObject private var spotifyService: SpotifyService
    @StateObject private var playbackTracker: PlaybackTracker
    
    @State private var chunks: [LyricChunk] = []
    @State private var currentChunk: LyricChunk?
    @State private var currentTrackName: String = ""
    
    private let processor = LyricProcessor()
    
    init(spDcCookie: String) {
        let service = SpotifyService(spDc: spDcCookie)
        _spotifyService = StateObject(wrappedValue: service)
        _playbackTracker = StateObject(wrappedValue: PlaybackTracker(spotifyService: service))
    }
    
    var body: some View {
        VStack(spacing: 20) {
            if !authManager.isAuthenticated {
                // Login view
                VStack(spacing: 15) {
                    Text("Connecting to Spotify")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Button("Login with Spotify") {
                        authManager.initiateLogin()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            } else {
                // Lyric view
                VStack(spacing: 10) {
                    Text(currentTrackName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    // ONLY show current chunk
                    if let chunk = currentChunk {
                        Text(chunk.text)
                            .font(.system(size: 48, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                            .padding()
                            .transition(.opacity)
                    } else {
                        Text("♪")
                            .font(.system(size: 48))
                            .foregroundColor(.gray)
                    }
                    
                    Spacer()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
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
        .onDisappear {
            playbackTracker.stopTracking()
        }
    }
    
    private func loadCurrentTrackLyrics() async {
        guard let track = spotifyService.currentTrack else { return }
        
        await MainActor.run {
            currentTrackName = "\(track.name) - \(track.artists.first?.name ?? "")"
        }
        
        do {
            let lines = try await spotifyService.fetchLyrics(for: track.id)
            let processedChunks = processor.process(lines: lines)
            
            await MainActor.run {
                chunks = processedChunks
            }
        } catch {
            print("Error loading lyrics: \(error)")
        }
    }
    
    private func updateCurrentChunk(for time: Double) {
        let active = chunks.first { chunk in
            time >= chunk.startTime && time < chunk.endTime
        }
        
        if currentChunk?.id != active?.id {
//            withAnimation(.easeInOut(duration: 0.2)) {
//                
//            }
            currentChunk = active
        }
    }
}

// MARK: - App Entry Point

//@main
struct LyricApp: App {
    var body: some Scene {
        WindowGroup {
            LyricDisplayView(spDcCookie: APIconstants.sp_dc)
                .frame(minWidth: 600, minHeight: 400)
        }
    }
}

