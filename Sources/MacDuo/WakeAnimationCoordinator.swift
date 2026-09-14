import Foundation

/// Keeps the clamshell sleep/wake sequence separate from ordinary desktop
/// animation state. The coordinator intentionally waits for both workspace
/// wake events before it permits a lock-screen window to appear, which filters
/// out dark wakes where the built-in display never turns on.
struct WakeAnimationCoordinator {
    /// A real clamshell sleep arrives only when the lid is nearly shut. This
    /// extra gate prevents a manual Sleep command at a partially closed angle
    /// from being mistaken for a lid-close cycle.
    private static let maximumClosedAngle: Double = 15

    struct Context: Equatable {
        let startAngle: Double
    }

    enum Phase: Equatable {
        case idle
        case armed(Context)
        case waking(Context, workspaceAwake: Bool, screenAwake: Bool)
        case opening(Context)
    }

    enum Action: Equatable {
        case none
        case start(Context)
        case cancel
    }

    private(set) var phase: Phase = .idle

    var isOpening: Bool {
        if case .opening = phase { return true }
        return false
    }

    var isPending: Bool {
        switch phase {
        case .armed, .waking:
            true
        case .idle, .opening:
            false
        }
    }

    mutating func armForSleep(
        effectWasActive: Bool,
        effectWasPreview: Bool,
        isEnabled: Bool,
        wasClosingRecently: Bool,
        startAngle: Double,
        currentAngle: Double
    ) {
        guard effectWasActive,
              !effectWasPreview,
              isEnabled,
              wasClosingRecently,
              currentAngle <= Self.maximumClosedAngle,
              currentAngle < startAngle else {
            phase = .idle
            return
        }
        phase = .armed(Context(startAngle: startAngle))
    }

    mutating func workspaceDidWake() {
        switch phase {
        case let .armed(context):
            phase = .waking(context, workspaceAwake: true, screenAwake: false)
        case let .waking(context, _, screenAwake):
            phase = .waking(context, workspaceAwake: true, screenAwake: screenAwake)
        case .idle, .opening:
            break
        }
    }

    mutating func screensDidWake() {
        switch phase {
        case let .armed(context):
            phase = .waking(context, workspaceAwake: false, screenAwake: true)
        case let .waking(context, workspaceAwake, _):
            phase = .waking(context, workspaceAwake: workspaceAwake, screenAwake: true)
        case .idle, .opening:
            break
        }
    }

    /// Starts from the first real post-wake sensor reading. If the lid is
    /// already beyond the release boundary there is nothing left to animate.
    mutating func observe(angle: Double, releaseHysteresis: Double) -> Action {
        guard case let .waking(context, workspaceAwake, screenAwake) = phase,
              workspaceAwake, screenAwake else { return .none }

        guard angle < context.startAngle + releaseHysteresis else {
            phase = .idle
            return .cancel
        }
        phase = .opening(context)
        return .start(context)
    }

    func shouldFinish(rawAngle: Double, visualAngle: Double, releaseHysteresis: Double) -> Bool {
        guard case let .opening(context) = phase else { return false }
        return rawAngle >= context.startAngle + releaseHysteresis
            && visualAngle >= context.startAngle - 0.5
    }

    mutating func finish() {
        phase = .idle
    }

    mutating func cancel() {
        phase = .idle
    }
}
