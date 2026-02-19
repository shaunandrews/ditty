import SwiftUI

struct ContentView: View {
    @StateObject private var bridge = MusicBridge()
    @State private var isFloating = true

    var body: some View {
        Group {
            if let track = bridge.track {
                playerView(track: track)
            } else {
                emptyView
            }
        }
        .background(.ultraThinMaterial)
        .cornerRadius(12)
    }

    private func playerView(track: TrackInfo) -> some View {
        HStack(spacing: 14) {
            // Album Art
            if let artwork = track.artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 80, height: 80)
                    .cornerRadius(8)
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.quaternary)
                    .frame(width: 80, height: 80)
                    .overlay {
                        Image(systemName: "music.note")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    }
            }

            // Track Info + Controls
            VStack(alignment: .leading, spacing: 4) {
                Text(track.title)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)

                Text(track.artist)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer()

                // Controls
                HStack(spacing: 16) {
                    Button(action: bridge.playPause) {
                        Image(systemName: track.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 18))
                    }
                    .buttonStyle(.plain)

                    Button(action: bridge.nextTrack) {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 16))
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    // Float toggle
                    Button(action: toggleFloat) {
                        Image(systemName: isFloating ? "pin.fill" : "pin.slash")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .help(isFloating ? "Unpin from top" : "Pin to top")
                }
            }

            Spacer(minLength: 0)
        }
        .padding(16)
    }

    private var emptyView: some View {
        HStack {
            Spacer()
            VStack(spacing: 6) {
                Image(systemName: "music.note")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text("Nothing playing")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(16)
    }

    private func toggleFloat() {
        isFloating.toggle()
        if let window = NSApplication.shared.windows.first {
            window.level = isFloating ? .floating : .normal
        }
    }
}
