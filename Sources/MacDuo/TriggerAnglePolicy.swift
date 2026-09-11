/// Resolves the angle at which a closing lid starts the effect.
///
/// The adaptive buffer delays the effect by requiring the lid to close farther.
/// Manual mode is unchanged.
enum TriggerAnglePolicy {
    static let validAngles: ClosedRange<Double> = 5...130
    static let adaptiveBufferRange: ClosedRange<Double> = 0...30

    static func resolvedStartAngle(
        manualAngle: Double,
        learnedAngle: Double?,
        adaptiveEnabled: Bool,
        adaptiveOffset: Double
    ) -> Double {
        let reference = adaptiveEnabled ? learnedAngle ?? manualAngle : manualAngle
        let boundedOffset = min(max(adaptiveOffset, adaptiveBufferRange.lowerBound), adaptiveBufferRange.upperBound)
        let adjusted = adaptiveEnabled ? reference - boundedOffset : reference
        return min(max(adjusted, validAngles.lowerBound), validAngles.upperBound)
    }
}
