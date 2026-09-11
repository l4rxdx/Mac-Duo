import Foundation

/// Learns a resting lid angle from a continuous window of stable readings.
///
/// The tracker is deliberately independent from the sensor and UI so its
/// timing and stability rules can be tested with synthetic samples.
struct AdaptiveAngleTracker {
    private struct Sample {
        let time: TimeInterval
        let angle: Double
    }

    /// A stable lid may still move slightly as the desk or display vibrates.
    private static let stabilityRange: Double = 1.2
    private static let validAngles: ClosedRange<Double> = 5...130
    private static let maximumSampleGap: TimeInterval = 2
    private static let minimumSampleCount = 4

    private var samples: [Sample] = []
    private var minimumAngle: Double = 0
    private var maximumAngle: Double = 0
    private var activeLearningDuration: TimeInterval?

    mutating func observe(
        angle: Double,
        at time: TimeInterval,
        learningDuration: TimeInterval,
        isLearningAllowed: Bool
    ) -> Double? {
        let duration = max(learningDuration, 0.1)

        guard isLearningAllowed, Self.validAngles.contains(angle) else {
            resetCandidate()
            activeLearningDuration = duration
            return nil
        }

        if let activeLearningDuration, abs(activeLearningDuration - duration) > 0.001 {
            resetCandidate()
        }
        activeLearningDuration = duration

        if let last = samples.last,
           time < last.time || time - last.time > Self.maximumSampleGap {
            resetCandidate()
        }

        if samples.isEmpty {
            beginCandidate(angle: angle, at: time)
            return nil
        }

        minimumAngle = min(minimumAngle, angle)
        maximumAngle = max(maximumAngle, angle)
        if maximumAngle - minimumAngle > Self.stabilityRange {
            beginCandidate(angle: angle, at: time)
            return nil
        }

        samples.append(Sample(time: time, angle: angle))
        guard let first = samples.first,
              samples.count >= Self.minimumSampleCount,
              time - first.time >= duration else { return nil }

        let learnedAngle = median(of: samples.map(\.angle))
        resetCandidate()
        return learnedAngle
    }

    mutating func reset() {
        resetCandidate()
        activeLearningDuration = nil
    }

    private mutating func beginCandidate(angle: Double, at time: TimeInterval) {
        samples = [Sample(time: time, angle: angle)]
        minimumAngle = angle
        maximumAngle = angle
    }

    private mutating func resetCandidate() {
        samples.removeAll(keepingCapacity: true)
        minimumAngle = 0
        maximumAngle = 0
    }

    private func median(of values: [Double]) -> Double {
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }
}
