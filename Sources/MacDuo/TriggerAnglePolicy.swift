/// Resolves the angle at which a closing lid starts the effect.
///
/// A positive adaptive offset delays the effect by requiring the lid to close
/// farther. A negative offset starts it earlier. Manual mode is unchanged.
enum TriggerAnglePolicy {
    static let validAngles: ClosedRange<Double> = 5...130
    static let adaptiveOffsetRange: ClosedRange<Double> = -30...30

    static func resolvedStartAngle(
        manualAngle: Double,
        learnedAngle: Double?,
        adaptiveEnabled: Bool,
        adaptiveOffset: Double
    ) -> Double {
        let reference = adaptiveEnabled ? learnedAngle ?? manualAngle : manualAngle
        let boundedOffset = min(max(adaptiveOffset, adaptiveOffsetRange.lowerBound), adaptiveOffsetRange.upperBound)
        let adjusted = adaptiveEnabled ? reference - boundedOffset : reference
        return min(max(adjusted, validAngles.lowerBound), validAngles.upperBound)
    }
}
