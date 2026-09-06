import Foundation

/// Aggregate PCM diagnostics without retaining the audio samples.
struct AudioSignalMetrics {
    private(set) var sampleCount = 0
    private(set) var nonZeroSampleCount = 0
    private(set) var peak = 0
    private var squaredSum: Double = 0

    var rms: Int {
        guard sampleCount > 0 else { return 0 }
        return Int((squaredSum / Double(sampleCount)).squareRoot())
    }

    mutating func append(_ samples: [Int16]) {
        for sample in samples {
            let value = Int(sample)
            sampleCount += 1
            if value != 0 { nonZeroSampleCount += 1 }
            peak = max(peak, abs(value))
            squaredSum += Double(value) * Double(value)
        }
    }
}
