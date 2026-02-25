import SwiftUI

class VisualizerSettings: ObservableObject {
    static let shared = VisualizerSettings()

    // Bar appearance
    @Published var barCount: Int = 64
    @Published var barSpacing: CGFloat = 1.5
    @Published var barCornerRadius: CGFloat = 1.5

    // Visualizer artwork (behind bars, within the artwork square)
    @Published var artworkDim: Double = 0.35
    @Published var backgroundBlur: CGFloat = 0
    @Published var barBlur: CGFloat = 0

    // Window background (blurred artwork behind everything)
    @Published var windowBgBlur: CGFloat = 25
    @Published var windowBgOpacity: Double = 0.85
    @Published var windowBgScale: Double = 1.6
    @Published var windowBgPulseSpeed: Double = 6

    // Dynamics
    @Published var decaySpeed: Float = 0.7
    @Published var highFreqBoost: Float = 2.5

    // Layout
    @Published var growthDirection: GrowthDirection = .center

    enum GrowthDirection: String, CaseIterable, Identifiable {
        case center = "Center"
        case bottom = "Bottom"
        case top = "Top"
        var id: String { rawValue }
    }

    /// Downsample 64 FFT bands to the desired display count
    func displayBands(from bands: [Float]) -> [Float] {
        guard barCount < bands.count else { return bands }
        let ratio = Float(bands.count) / Float(barCount)
        return (0..<barCount).map { i in
            let lo = Int(Float(i) * ratio)
            let hi = min(bands.count, Int(Float(i + 1) * ratio))
            guard hi > lo else { return bands[lo] }
            return (lo..<hi).map { bands[$0] }.max() ?? 0
        }
    }
}
