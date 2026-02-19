import AppKit
import Combine
import Foundation

struct TrackInfo: Equatable {
    var title: String
    var artist: String
    var album: String
    var artwork: NSImage?
    var isPlaying: Bool
    var duration: Double
    var position: Double
}

class MusicBridge: ObservableObject {
    @Published var track: TrackInfo?
    private var timer: Timer?

    init() {
        startPolling()
    }

    func startPolling() {
        poll() // immediate first fetch
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.poll()
        }
    }

    func poll() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let info = self?.fetchTrackInfo()
            DispatchQueue.main.async {
                self?.track = info
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

        let artwork = fetchArtwork()

        return TrackInfo(
            title: parts[0],
            artist: parts[1],
            album: parts[2],
            artwork: artwork,
            isPlaying: parts[5] == "true",
            duration: Double(parts[3]) ?? 0,
            position: Double(parts[4]) ?? 0
        )
    }

    private func fetchArtwork() -> NSImage? {
        let script = """
        tell application "Music"
            if player state is not stopped then
                try
                    set artworkData to raw data of artwork 1 of current track
                    return artworkData
                end try
            end if
        end tell
        """

        guard let appleScript = NSAppleScript(source: script) else { return nil }
        var error: NSDictionary?
        let result = appleScript.executeAndReturnError(&error)

        if error != nil { return nil }

        // Get the raw data from the Apple event descriptor
        let data = result.data
        if let imageData = data {
            return NSImage(data: imageData)
        }

        return nil
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
