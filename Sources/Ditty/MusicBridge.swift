import AppKit
import Combine
import Foundation

struct TrackInfo {
    var title: String
    var artist: String
    var album: String
    var artwork: NSImage?
    var isPlaying: Bool
    var duration: Double
    var position: Double
}

// Excludes artwork (NSImage reference equality would defeat caching),
// position (changes every poll — include when adding a progress UI),
// and duration (constant per track).
extension TrackInfo: Equatable {
    static func == (lhs: TrackInfo, rhs: TrackInfo) -> Bool {
        lhs.title == rhs.title
            && lhs.artist == rhs.artist
            && lhs.album == rhs.album
            && lhs.isPlaying == rhs.isPlaying
    }
}

extension NSImage {
    var averageLuminance: CGFloat {
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 1, pixelsHigh: 1,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 4, bitsPerPixel: 32
        ) else { return 0.5 }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        draw(in: NSRect(x: 0, y: 0, width: 1, height: 1),
             from: NSRect(origin: .zero, size: size),
             operation: .copy, fraction: 1.0)
        NSGraphicsContext.restoreGraphicsState()

        guard let c = bitmap.colorAt(x: 0, y: 0) else { return 0.5 }
        return 0.299 * c.redComponent + 0.587 * c.greenComponent + 0.114 * c.blueComponent
    }
}

class MusicBridge: ObservableObject {
    @Published var track: TrackInfo?
    @Published var isLightArtwork: Bool = false
    private var timer: Timer?
    private var cachedArtwork: NSImage?
    private var lastTrackKey: String?
    private let stateQueue = DispatchQueue(label: "MusicBridge.state")

    init() {
        startPolling()
    }

    deinit {
        timer?.invalidate()
    }

    func startPolling() {
        poll() // immediate first fetch
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.poll()
        }
    }

    func poll() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            guard var info = self.fetchTrackInfo() else {
                DispatchQueue.main.async { self.track = nil }
                return
            }

            let trackKey = "\(info.title)||\(info.artist)||\(info.album)"

            let artwork: NSImage? = self.stateQueue.sync {
                if trackKey != self.lastTrackKey {
                    let fresh = self.fetchArtwork(artist: info.artist, album: info.album)
                    self.cachedArtwork = fresh
                    self.lastTrackKey = trackKey
                    return fresh
                } else {
                    return self.cachedArtwork
                }
            }

            let isLight = artwork?.averageLuminance ?? 0.5 > 0.5

            DispatchQueue.main.async {
                info.artwork = artwork
                self.track = info
                self.isLightArtwork = isLight
            }
        }
    }

    private func fetchTrackInfo() -> TrackInfo? {
        let script = """
        tell application "Music"
            if player state is not stopped then
                set trackName to name of current track
                set trackArtist to artist of current track
                set trackAlbum to album of current track
                set trackDuration to duration of current track
                set trackPosition to player position
                set isPlaying to (player state is playing)
                return trackName & "||" & trackArtist & "||" & trackAlbum & "||" & trackDuration & "||" & trackPosition & "||" & isPlaying
            else
                return "STOPPED"
            end if
        end tell
        """

        guard let appleScript = NSAppleScript(source: script) else { return nil }
        var error: NSDictionary?
        let result = appleScript.executeAndReturnError(&error)

        if error != nil { return nil }
        let output = result.stringValue ?? ""
        if output == "STOPPED" { return nil }

        let parts = output.components(separatedBy: "||")
        guard parts.count >= 6 else { return nil }

        return TrackInfo(
            title: parts[0],
            artist: parts[1],
            album: parts[2],
            artwork: nil,
            isPlaying: parts[5] == "true",
            duration: Double(parts[3]) ?? 0,
            position: Double(parts[4]) ?? 0
        )
    }

    private func fetchArtwork(artist: String, album: String) -> NSImage? {
        // Try embedded artwork via AppleScript (local tracks)
        if let image = fetchArtworkViaAppleScript() { return image }
        // Fall back to iTunes Search API (streaming/Apple Music tracks)
        return fetchArtworkViaSearch(artist: artist, album: album)
    }

    private func fetchArtworkViaAppleScript() -> NSImage? {
        let tmpPath = NSTemporaryDirectory() + "music_controller_artwork.dat"
        let script = """
        tell application "Music"
            if player state is not stopped then
                if (count of artworks of current track) > 0 then
                    set artData to raw data of artwork 1 of current track
                    set tmpPath to "\(tmpPath)"
                    set fileRef to open for access (POSIX file tmpPath) with write permission
                    set eof fileRef to 0
                    write artData to fileRef
                    close access fileRef
                    return tmpPath
                end if
            end if
        end tell
        """

        guard let appleScript = NSAppleScript(source: script) else { return nil }
        var error: NSDictionary?
        let result = appleScript.executeAndReturnError(&error)

        if error != nil { return nil }
        guard let path = result.stringValue, !path.isEmpty else { return nil }
        return NSImage(contentsOfFile: path)
    }

    private func fetchArtworkViaSearch(artist: String, album: String) -> NSImage? {
        let query = "\(artist) \(album)"
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        guard let url = URL(string: "https://itunes.apple.com/search?term=\(query)&entity=album&limit=1"),
              let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]],
              let first = results.first,
              let artworkUrl = first["artworkUrl100"] as? String else { return nil }

        let hiRes = artworkUrl.replacingOccurrences(of: "100x100", with: "600x600")
        guard let imageUrl = URL(string: hiRes),
              let imageData = try? Data(contentsOf: imageUrl) else { return nil }
        return NSImage(data: imageData)
    }

    // MARK: - Controls

    func playPause() {
        runScript("tell application \"Music\" to playpause")
    }

    func nextTrack() {
        runScript("tell application \"Music\" to next track")
    }

    func previousTrack() {
        runScript("tell application \"Music\" to previous track")
    }

    private func runScript(_ source: String) {
        DispatchQueue.global(qos: .userInitiated).async {
            let script = NSAppleScript(source: source)
            var error: NSDictionary?
            script?.executeAndReturnError(&error)
        }
        // Immediately poll to update UI
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.poll()
        }
    }
}
