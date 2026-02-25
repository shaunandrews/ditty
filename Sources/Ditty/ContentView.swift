import SwiftUI

// MARK: - Audio Visualizer

struct AudioVisualizerView: View {
    let bands: [Float]
    let artwork: NSImage?
    var height: CGFloat = 36
    @ObservedObject private var settings = VisualizerSettings.shared

    private var displayBands: [Float] {
        settings.displayBands(from: bands)
    }

    private var alignment: Alignment {
        switch settings.growthDirection {
        case .center: return .center
        case .bottom: return .bottom
        case .top: return .top
        }
    }

    var body: some View {
        ZStack {
            // Bars mask the artwork — album art bleeds through
            if let artwork = artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(height: height)
                    .clipped()
                    .blur(radius: settings.barBlur)
                    .mask {
                        barMask
                    }
            } else {
                // No artwork — faint white bars
                barMask
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
        .frame(height: height)
        .animation(.linear(duration: 0.06), value: displayBands.map { $0 })
    }

    private var barMask: some View {
        HStack(spacing: settings.barSpacing) {
            ForEach(Array(displayBands.enumerated()), id: \.offset) { _, level in
                RoundedRectangle(cornerRadius: settings.barCornerRadius)
                    .frame(maxWidth: .infinity)
                    .frame(height: max(2, CGFloat(level) * height))
            }
        }
        .frame(height: height, alignment: alignment)
    }
}

// MARK: - Content View

struct ContentView: View {
    @StateObject private var bridge = MusicBridge()
    @StateObject private var audio = AudioAnalyzer()
    @ObservedObject private var settings = VisualizerSettings.shared
    @State private var isFloating = true
    @State private var isHovering = false
    @State private var pulseBackground = false

    private var primaryColor: Color {
        bridge.isLightArtwork ? .black.opacity(0.85) : .white.opacity(0.95)
    }

    private var secondaryColor: Color {
        bridge.isLightArtwork ? .black.opacity(0.5) : .white.opacity(0.6)
    }

    var body: some View {
        GeometryReader { geo in
            let compact = geo.size.width < 220

            Group {
                if let track = bridge.track {
                    playerView(track: track, compact: compact)
                } else {
                    emptyView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .background {
            if let artwork = bridge.track?.artwork {
                let spread = settings.windowBgScale * 0.15
                Image(nsImage: artwork)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .blur(radius: settings.windowBgBlur)
                    .scaleEffect(pulseBackground
                        ? settings.windowBgScale + spread
                        : settings.windowBgScale - spread)
                    .rotationEffect(.degrees(pulseBackground ? 4 : -4))
                    .opacity(settings.windowBgOpacity)
                    .animation(
                        .easeInOut(duration: settings.windowBgPulseSpeed)
                            .repeatForever(autoreverses: true),
                        value: pulseBackground
                    )
                    .onAppear { pulseBackground = true }
            }
        }
        .background(.ultraThinMaterial)
        .cornerRadius(12)
        .onHover { hovering in
            isHovering = hovering
        }
        .onAppear {
            audio.start()
        }
    }

    private func playerView(track: TrackInfo, compact: Bool) -> some View {
        VStack(spacing: 0) {
            if !compact {
                // Album Art with visualizer overlay
                GeometryReader { artGeo in
                    ZStack(alignment: .bottom) {
                        // Dimmed artwork background
                        if let artwork = track.artwork {
                            Image(nsImage: artwork)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: artGeo.size.width, height: artGeo.size.width)
                                .clipped()
                                .blur(radius: settings.backgroundBlur)
                                .brightness(-settings.artworkDim)
                        } else {
                            Rectangle()
                                .fill(.quaternary)
                                .overlay {
                                    Image(systemName: "music.note")
                                        .font(.system(size: 40))
                                        .foregroundStyle(secondaryColor)
                                }
                        }

                        // Visualizer — bars illuminate the artwork
                        AudioVisualizerView(
                            bands: audio.bands,
                            artwork: track.artwork,
                            height: artGeo.size.width
                        )

                        // Controls + pin buttons — top corners
                        if isHovering {
                            VStack {
                                HStack {
                                    controlsButton
                                    Spacer()
                                    pinButton
                                }
                                Spacer()
                            }
                        }
                    }
                }
                .aspectRatio(1, contentMode: .fit)
                .clipped()
            } else {
                // Compact: small visualizer strip
                AudioVisualizerView(
                    bands: audio.bands,
                    artwork: track.artwork,
                    height: 36
                )
                .padding(.horizontal, 8)
                .padding(.top, 8)
            }

            // Track info + controls
            VStack(spacing: 2) {
                Text(track.title)
                    .font(.system(size: compact ? 12 : 14, weight: .semibold))
                    .foregroundStyle(primaryColor)
                    .lineLimit(1)

                Text(track.artist)
                    .font(.system(size: compact ? 10 : 12))
                    .foregroundStyle(secondaryColor)
                    .lineLimit(1)

                HStack(spacing: compact ? 14 : 20) {
                    Button(action: bridge.previousTrack) {
                        Image(systemName: "backward.fill")
                            .font(.system(size: compact ? 12 : 16))
                    }
                    .buttonStyle(.plain)

                    Button(action: bridge.playPause) {
                        Image(systemName: track.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: compact ? 14 : 20))
                    }
                    .buttonStyle(.plain)

                    Button(action: bridge.nextTrack) {
                        Image(systemName: "forward.fill")
                            .font(.system(size: compact ? 12 : 16))
                    }
                    .buttonStyle(.plain)
                }
                .foregroundStyle(primaryColor)
                .padding(.top, compact ? 6 : 10)

                if compact && isHovering {
                    pinButton
                        .padding(.top, 4)
                }
            }
            .padding(.top, 8)
            .padding(.bottom, compact ? 10 : 16)
            .padding(.horizontal, 16)
        }
    }

    private var controlsButton: some View {
        Button(action: { ControlsPanelManager.shared.toggle() }) {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.8))
                .padding(6)
                .background(.black.opacity(0.4))
                .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .help("Visualizer controls")
        .padding(8)
        .transition(.opacity)
    }

    private var pinButton: some View {
        Button(action: toggleFloat) {
            Image(systemName: isFloating ? "pin.fill" : "pin.slash")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.8))
                .padding(6)
                .background(.black.opacity(0.4))
                .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .help(isFloating ? "Unpin from top" : "Pin to top")
        .padding(8)
        .transition(.opacity)
    }

    private var emptyView: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "music.note")
                .font(.system(size: 32))
                .foregroundStyle(secondaryColor)
            Text("Nothing playing")
                .font(.system(size: 13))
                .foregroundStyle(secondaryColor)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func toggleFloat() {
        isFloating.toggle()
        if let window = NSApplication.shared.windows.first {
            window.level = isFloating ? .floating : .normal
        }
    }
}
