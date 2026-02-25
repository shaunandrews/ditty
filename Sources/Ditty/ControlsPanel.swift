import SwiftUI
import Cocoa

// MARK: - Window Management

class ControlsPanelManager {
    static let shared = ControlsPanelManager()
    private var panel: NSPanel?

    func toggle() {
        if let panel, panel.isVisible {
            panel.close()
            return
        }
        show()
    }

    func show() {
        if let panel {
            panel.makeKeyAndOrderFront(nil)
            return
        }

        let hostingView = NSHostingView(
            rootView: ControlsPanel()
                .environment(\.colorScheme, .dark)
        )
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 580),
            styleMask: [.titled, .closable, .utilityWindow, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = "Visualizer"
        panel.contentView = hostingView
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.isMovableByWindowBackground = true
        panel.appearance = NSAppearance(named: .vibrantDark)
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        self.panel = panel
    }
}

// MARK: - Controls UI

struct ControlsPanel: View {
    @ObservedObject private var settings = VisualizerSettings.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 2) {
                card("waveform.path.ecg", "Bars") {
                    row("Direction") {
                        Picker("", selection: $settings.growthDirection) {
                            ForEach(VisualizerSettings.GrowthDirection.allCases) { dir in
                                Text(dir.rawValue).tag(dir)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(maxWidth: 150)
                    }
                    slider("Count", value: intBinding($settings.barCount), in: 8...128, step: 8) {
                        "\(settings.barCount)"
                    }
                    slider("Gap", value: cgBinding($settings.barSpacing), in: 0...6, step: 0.5) {
                        String(format: "%.1f", settings.barSpacing)
                    }
                    slider("Roundness", value: cgBinding($settings.barCornerRadius), in: 0...8, step: 0.5) {
                        String(format: "%.1f", settings.barCornerRadius)
                    }
                    slider("Blur", value: cgBinding($settings.barBlur), in: 0...20) {
                        String(format: "%.0f", settings.barBlur)
                    }
                }

                card("photo.artframe", "Artwork") {
                    slider("Dim", value: $settings.artworkDim, in: 0...0.8) {
                        "\(Int(settings.artworkDim * 100))%"
                    }
                    slider("Blur", value: cgBinding($settings.backgroundBlur), in: 0...30) {
                        String(format: "%.0f", settings.backgroundBlur)
                    }
                }

                card("sparkles.rectangle.stack", "Ambience") {
                    slider("Blur", value: cgBinding($settings.windowBgBlur), in: 0...60) {
                        String(format: "%.0f", settings.windowBgBlur)
                    }
                    slider("Opacity", value: $settings.windowBgOpacity, in: 0...1) {
                        "\(Int(settings.windowBgOpacity * 100))%"
                    }
                    slider("Zoom", value: $settings.windowBgScale, in: 1...3) {
                        String(format: "%.1fx", settings.windowBgScale)
                    }
                    slider("Pulse", value: $settings.windowBgPulseSpeed, in: 1...20) {
                        String(format: "%.0fs", settings.windowBgPulseSpeed)
                    }
                }

                card("bolt.fill", "Dynamics") {
                    slider("Decay", value: floatBinding($settings.decaySpeed), in: 0.3...0.95) {
                        String(format: "%.2f", settings.decaySpeed)
                    }
                    slider("Treble", value: floatBinding($settings.highFreqBoost), in: 0...5) {
                        String(format: "+%.1f", settings.highFreqBoost)
                    }
                }
            }
            .padding(10)
        }
        .frame(width: 300)
        .background(Color(white: 0.12))
    }

    // MARK: - Card

    private func card<Content: View>(
        _ icon: String,
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))
                    .textCase(.uppercase)
                    .tracking(0.8)
            }
            .padding(.horizontal, 2)

            VStack(spacing: 8) {
                content()
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.06))
        .cornerRadius(10)
    }

    // MARK: - Controls

    private func row<Content: View>(
        _ label: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.8))
            Spacer()
            content()
        }
    }

    private func slider(
        _ label: String,
        value: Binding<Double>,
        in range: ClosedRange<Double>,
        step: Double? = nil,
        display: () -> String
    ) -> some View {
        VStack(spacing: 3) {
            HStack {
                Text(label)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.8))
                Spacer()
                Text(display())
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.4))
            }
            Group {
                if let step {
                    Slider(value: value, in: range, step: step)
                } else {
                    Slider(value: value, in: range)
                }
            }
            .tint(.white.opacity(0.5))
        }
    }

    // MARK: - Bindings

    private func intBinding(_ b: Binding<Int>) -> Binding<Double> {
        Binding(get: { Double(b.wrappedValue) }, set: { b.wrappedValue = Int($0) })
    }

    private func floatBinding(_ b: Binding<Float>) -> Binding<Double> {
        Binding(get: { Double(b.wrappedValue) }, set: { b.wrappedValue = Float($0) })
    }

    private func cgBinding(_ b: Binding<CGFloat>) -> Binding<Double> {
        Binding(get: { Double(b.wrappedValue) }, set: { b.wrappedValue = CGFloat($0) })
    }
}
