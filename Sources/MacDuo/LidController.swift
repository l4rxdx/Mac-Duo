import AppKit
import Combine
import LidAngleKit
import QuartzCore

/// Watches the lid angle and drives the depth effect overlay.
///
/// A timer polls the sensor, and a display link advances a spring at the
/// screen refresh rate so the ramp stays smooth between readings.

/// Identity of the built-in display. `NSApplication` posts a screen change for
/// a backlight change too, and this tells the two apart.
struct Layout: Equatable {
    var displayID: CGDirectDisplayID?
    var frame: CGRect?
}

/// `IOHIDDeviceGetReport` is synchronous and takes a few milliseconds. Keep it
/// on one dedicated queue so a slow read cannot make the display link miss a
/// refresh. All access after startup is serialized by `readQueue`.
private final class LidSensorReader: @unchecked Sendable {
    let sensor = LidAngleSensor()

    var isAvailable: Bool { sensor.isAvailable }
    func angle() -> Double? { sensor.angle() }
}

@MainActor
final class LidController: NSObject, ObservableObject, @preconcurrency CAMetalDisplayLinkDelegate {

    @Published private(set) var currentAngle: Double = 0
    @Published private(set) var isSensorAvailable = false
    @Published private(set) var isActive = false

    let snapshotter = ScreenSnapshotter()

    private let preferences: Preferences
    private let sensorReader = LidSensorReader()
    private let readQueue = DispatchQueue(label: "MacDuo.lidSensor", qos: .userInteractive)
    private let overlay = DepthOverlay()
    private let streamer = ScreenStreamer()

    private var pollTimer: Timer?
    private var pollInterval: TimeInterval = 0
    private var displayLink: CAMetalDisplayLink?
    private var lastFrameTime: CFTimeInterval = 0
    private var lastPublishTime: CFTimeInterval = 0
    private var displayFrameCount: UInt64 = 0
    private var submittedDisplayFrameCount: UInt64 = 0
    private var firstDisplayFrameTime: CFTimeInterval?
    private var slowDisplayFrameCount: UInt64 = 0
    private var longestDisplayFrameInterval: TimeInterval = 0
    private var slowDisplayWorkCount: UInt64 = 0
    private var longestDisplayWorkDuration: TimeInterval = 0

    private var rawAngle: Double = 0
    /// Degrees per second, negative while the lid closes.
    private var angularVelocity: Double = 0
    private var lastChangedAngle: Double?
    private var lastChangeTime: CFTimeInterval = 0
    private var lastClosingTime: CFTimeInterval = -.greatestFiniteMagnitude
    private var visualAngle = CriticallyDampedSpring()
    private var consecutiveFailedReads = 0
    private var startedAt: CFTimeInterval = 0
    private var preview: PreviewRun?
    private var isSuspended = false
    private var isSensorReadPending = false
    private var isCapturePending = false
    private var lastMovedDownTime: CFTimeInterval = -.greatestFiniteMagnitude
    private var lastMeaningfulMotionTime: CFTimeInterval = -.greatestFiniteMagnitude
    private var effectStartAngle: Double?
    private var adaptiveAngleTracker = AdaptiveAngleTracker()
    private var builtInLayout = Layout()

    private static let idlePollInterval: TimeInterval = 1.0 / 8
    private static let activePollInterval: TimeInterval = 1.0 / 30
    private static let targetFramesPerSecond: Float = 60
    private static let slowDisplayFrameInterval: TimeInterval = 1.0 / 45
    private static let slowDisplayWorkDuration: TimeInterval = 1.0 / 120
    private static let fadeInDuration: TimeInterval = 0.07
    /// Degrees above the pre-warm zone at which polling speeds up.
    private static let fastPollMargin: Double = 20

    /// Closing speed that counts as a deliberate close, in degrees per second.
    /// A still lid reads under 0.5.
    private static let triggerClosingSpeed: Double = 2

    /// How long after the lid last moved down the effect may still start.
    private static let closingMemory: TimeInterval = 1.5

    private static let predictionSpeedFloor: Double = 40

    /// Sensor latency the prediction adds on top of the reading's own age.
    private static let predictionLatency: TimeInterval = 0.04

    /// The overlay stays up at least this long. A prediction can fire while the
    /// last reading is still above the release angle.
    private static let minimumEffectDuration: TimeInterval = 0.35

    /// In adaptive mode, a stopped lid becomes a new resting-angle candidate.
    private static let adaptiveSettleReleaseDelay: TimeInterval = 2

    /// Movement below this speed is treated as normal sensor or desk noise.
    private static let meaningfulMotionSpeed: Double = 0.75

    /// A scripted angle sweep, so the settings panel can show the effect
    /// without the lid moving. It feeds the same path the sensor feeds.
    private struct PreviewRun {
        let startedAt: CFTimeInterval
        let open: Double
        let shut: Double
        let closing: CFTimeInterval = 1.4
        let hold: CFTimeInterval = 0.8
        let opening: CFTimeInterval = 0.6

        /// `nil` once the run is over.
        func angle(at now: CFTimeInterval) -> Double? {
            let elapsed = now - startedAt
            if elapsed < closing { return open + (shut - open) * (elapsed / closing) }
            if elapsed < closing + hold { return shut }
            if elapsed < closing + hold + opening {
                return shut + (open - shut) * ((elapsed - closing - hold) / opening)
            }
            return nil
        }
    }

    init(preferences: Preferences) {
        self.preferences = preferences
        super.init()
    }

    // MARK: - Lifecycle

    func start() {
        isSensorAvailable = sensorReader.isAvailable
        guard isSensorAvailable else { return }

        if let angle = sensorReader.angle() {
            rawAngle = angle
            currentAngle = angle
            visualAngle.reset(to: angle)
        }
        setPollInterval(Self.idlePollInterval)
        builtInLayout = Layout(displayID: NSScreen.builtIn?.displayID, frame: NSScreen.builtIn?.frame)
        observeSystemEvents()
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("to.maki.MacDuo.preview"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.runPreview() }
        }
        overlay.warmUp()
        if preferences.isLivePicture, let screen = NSScreen.builtIn {
            overlay.prepareLive(on: screen)
        }
        Task {
            await snapshotter.warmFilter()
            // After the overlay has put its presence window up, so the filter
            // can name this app and leave the overlay out of the picture.
            try? await Task.sleep(nanoseconds: 500_000_000)
            await streamer.warmFilter()
        }
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
        pollInterval = 0
        stopDisplayLink()
        overlay.dismiss(animated: false)
        snapshotter.endPrewarm()
        streamer.stop()
        overlay.discardLive()
        isActive = false
        effectStartAngle = nil
        adaptiveAngleTracker.reset()
    }

    /// Plays the effect once on the current screen contents.
    func runPreview() {
        guard preview == nil, !isActive else { return }
        let startAngle = effectiveStartAngle
        // Well above the trigger angle, so the sweep runs the pre-warm the way
        // a real close does.
        preview = PreviewRun(
            startedAt: CACurrentMediaTime(),
            open: min(startAngle + 35, 130),
            shut: max(startAngle - preferences.blurSpan * 1.15, 5)
        )
        setPollInterval(Self.activePollInterval)
    }

    // MARK: - Polling

    private func setPollInterval(_ interval: TimeInterval) {
        guard pollInterval != interval else { return }
        pollInterval = interval
        pollTimer?.invalidate()
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    private func poll() {
        guard !isSuspended else { return }

        if let run = preview {
            guard let scripted = run.angle(at: CACurrentMediaTime()) else {
                preview = nil
                return
            }
            accept(angle: scripted)
            return
        }

        guard !isSensorReadPending else { return }
        isSensorReadPending = true
        let reader = sensorReader
        readQueue.async { [weak self] in
            let angle = reader.angle()
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.isSensorReadPending = false
                    guard !self.isSuspended, self.preview == nil else { return }
                    self.acceptSensorRead(angle)
                }
            }
        }
    }

    private func acceptSensorRead(_ angle: Double?) {
        guard let angle else {
            consecutiveFailedReads += 1
            if consecutiveFailedReads > 30, isActive {
                Diagnostics.lid.notice(
                    """
                    release: sensor read failed \(self.consecutiveFailedReads) times in a row, \
                    last angle \(self.rawAngle, format: .fixed(precision: 2))
                    """
                )
                setActive(false)
            }
            return
        }
        if consecutiveFailedReads > 0 {
            Diagnostics.lid.notice(
                "sensor recovered after \(self.consecutiveFailedReads) failed reads, angle \(angle, format: .fixed(precision: 2))"
            )
        }
        consecutiveFailedReads = 0
        accept(angle: angle)
    }

    private func accept(angle: Double) {
        let now = CACurrentMediaTime()
        rawAngle = angle
        updateVelocity(with: angle, at: now)
        publish(angle: angle)
        updateAdaptiveAngle(with: angle, at: now)

        reconcile(angle: angle)

        let prewarmZone = effectiveStartAngle + preferences.prewarmCeiling
        let wantsFastPolling = preview != nil || isActive || angle <= prewarmZone + Self.fastPollMargin
        setPollInterval(wantsFastPolling ? Self.activePollInterval : Self.idlePollInterval)
    }

    /// Whether the picture belongs on screen for this angle. It widens the
    /// angle for release and keeps a lid held below the angle showing.
    private func wantsEffect(angle: Double) -> Bool {
        guard preferences.isEnabled else { return false }
        let threshold = effectStartAngle ?? effectiveStartAngle
        if isActive {
            guard CACurrentMediaTime() - startedAt > Self.minimumEffectDuration else { return true }
            if preferences.isAdaptiveTriggerAngleEnabled,
               CACurrentMediaTime() - lastMeaningfulMotionTime >= Self.adaptiveSettleReleaseDelay {
                return false
            }
            return angle < threshold + preferences.hysteresis
        }
        // A lid resting below the angle must not start by itself.
        let closing = CACurrentMediaTime() - lastMovedDownTime < Self.closingMemory
        return closing && predictedAngle() <= threshold
    }

    /// Brings the screen in line with `wantsEffect` on every sample. A run
    /// whose screenshot failed is retried here.
    private func reconcile(angle: Double) {
        let wanted = wantsEffect(angle: angle)
        if wanted != isActive {
            Diagnostics.lid.notice(
                """
                \(wanted ? "start" : "end", privacy: .public) raw \(angle, format: .fixed(precision: 2)) \
                predicted \(self.predictedAngle(), format: .fixed(precision: 2)) \
                velocity \(self.angularVelocity, format: .fixed(precision: 1)) deg/s \
                snapshot \(self.snapshotter.latestImage != nil)
                """
            )
            setActive(wanted)
            return
        }
        if isActive {
            if !overlay.isVisible, !isCapturePending { presentPicture() }
            // A visible overlay with no link would sit at its first frame.
            if overlay.isVisible, displayLink == nil { startDisplayLink() }
        } else {
            updatePrewarm(angle: angle, ceiling: effectiveStartAngle + preferences.prewarmCeiling)
        }
    }

    private func updateVelocity(with angle: Double, at now: CFTimeInterval) {
        guard let last = lastChangedAngle else {
            lastChangedAngle = angle
            lastChangeTime = now
            return
        }
        if angle != last {
            let dt = now - lastChangeTime
            if dt > 0.001 {
                let instant = (angle - last) / dt
                angularVelocity = 0.5 * instant + 0.5 * angularVelocity
            }
            lastChangedAngle = angle
            lastChangeTime = now
        } else if now - lastChangeTime > 0.4 {
            angularVelocity = 0
        }
        if angularVelocity <= -Self.triggerClosingSpeed {
            lastMovedDownTime = now
        }
        if angularVelocity <= -preferences.closingSpeed {
            lastClosingTime = now
        }
        if abs(angularVelocity) >= Self.meaningfulMotionSpeed {
            lastMeaningfulMotionTime = now
        }
    }

    private func updateAdaptiveAngle(with angle: Double, at now: CFTimeInterval) {
        let mayLearn = preferences.isAdaptiveTriggerAngleEnabled && preview == nil && !isActive
        guard let learned = adaptiveAngleTracker.observe(
            angle: angle,
            at: now,
            learningDuration: preferences.adaptiveLearningDuration,
            isLearningAllowed: mayLearn
        ) else { return }

        if preferences.acceptLearnedTriggerAngle(learned) {
            Diagnostics.lid.notice("adaptive trigger learned at \(learned, format: .fixed(precision: 2)) degrees")
        }
    }

    /// Runs only while the lid is closing, so holding it still does not leave
    /// a capture loop running.
    private func updatePrewarm(angle: Double, ceiling: Double) {
        let closingRecently = CACurrentMediaTime() - lastClosingTime < preferences.prewarmLinger
        guard angle <= ceiling, closingRecently else {
            snapshotter.endPrewarm()
            streamer.stop()
            overlay.discardLive()
            return
        }
        guard preferences.isLivePicture else {
            streamer.stop()
            overlay.discardLive()
            snapshotter.beginPrewarm(interval: preferences.prewarmInterval)
            return
        }
        // Only the stream. Asking ScreenCaptureKit for a screenshot at the
        // same time makes it serve neither quickly.
        snapshotter.endPrewarm()
        if let screen = NSScreen.builtIn { overlay.prepareLive(on: screen) }
        streamer.start()
    }

    /// A reading can be a full sensor refresh old, so a fast close works from
    /// where the lid is heading rather than the last reading.
    private func predictedAngle() -> Double {
        guard angularVelocity < -Self.predictionSpeedFloor else { return rawAngle }
        let staleness = min(CACurrentMediaTime() - lastChangeTime, 0.12)
        return rawAngle + angularVelocity * (staleness + Self.predictionLatency)
    }

    private func publish(angle: Double) {
        let now = CACurrentMediaTime()
        guard now - lastPublishTime > 0.08 else { return }
        lastPublishTime = now
        if abs(currentAngle - angle) > 0.001 { currentAngle = angle }
    }

    // MARK: - Depth effect

    private func setActive(_ active: Bool) {
        if active { effectStartAngle = effectiveStartAngle }
        isActive = active
        if active {
            startedAt = CACurrentMediaTime()
            visualAngle.reset(to: rawAngle)
            snapshotter.endPrewarm()
            setPollInterval(Self.activePollInterval)
            presentPicture()
        } else {
            stopDisplayLink()
            overlay.dismiss(animated: true)
            snapshotter.discard()
            effectStartAngle = nil
        }
    }

    private func endEffect() {
        setActive(false)
    }

    /// Shows the held screenshot, or waits for one. A pre-warm capture that is
    /// already running counts as that wait.
    private func presentPicture() {
        if preferences.isLivePicture, let screen = NSScreen.builtIn,
           overlay.showLive(
               on: screen,
               startAngle: effectStartAngle ?? effectiveStartAngle,
               tuning: tuning,
               fadeIn: Self.fadeInDuration
           ) {
            startDisplayLink()
            if let frame = streamer.newFrame() {
                Diagnostics.lid.notice("present: live, a stream frame was ready")
                overlay.absorb(frame)
                return
            }
            // A fast close can reach the trigger angle before the stream has a
            // frame. One screenshot starts the picture off.
            if let image = snapshotter.latestImage {
                Diagnostics.lid.notice("present: live, seeding from the pre-warm screenshot")
                overlay.seed(image: image)
                return
            }
            Diagnostics.lid.notice("present: live, no picture yet, asking for a screenshot")
            requestSeed()
            return
        }

        if let image = snapshotter.latestImage, let screen = snapshotter.latestScreen {
            show(image: image, on: screen)
            return
        }
        isCapturePending = true
        Task { [weak self] in
            guard let self else { return }
            await self.snapshotter.captureOnce()
            self.isCapturePending = false
            Diagnostics.lid.notice(
                """
                capture landed: image \(self.snapshotter.latestImage != nil) \
                on \(self.isActive) overlay \(self.overlay.isVisible)
                """
            )
            guard self.isActive, !self.overlay.isVisible,
                  let image = self.snapshotter.latestImage,
                  let screen = self.snapshotter.latestScreen else { return }
            self.show(image: image, on: screen)
        }
    }

    /// Takes one screenshot to start a live overlay that has nothing to show
    /// yet. A stream frame that lands first makes it unnecessary.
    private func requestSeed() {
        isCapturePending = true
        let started = CACurrentMediaTime()
        Task { [weak self] in
            guard let self else { return }
            await self.snapshotter.captureOnce()
            self.isCapturePending = false
            Diagnostics.lid.notice(
                """
                seed capture landed after \((CACurrentMediaTime() - started) * 1000, format: .fixed(precision: 0)) ms: \
                image \(self.snapshotter.latestImage != nil) on \(self.isActive) \
                ready \(self.overlay.isPictureReady)
                """
            )
            guard self.isActive, !self.overlay.isPictureReady,
                  let image = self.snapshotter.latestImage else { return }
            self.overlay.seed(image: image)
        }
    }

    private func show(image: CGImage, on screen: NSScreen) {
        overlay.show(
            image: image,
            on: screen,
            startAngle: effectStartAngle ?? effectiveStartAngle,
            tuning: tuning,
            fadeIn: Self.fadeInDuration
        )
        // The link belongs to the overlay window.
        startDisplayLink()
    }

    private func blurProgress(for angle: Double) -> Double {
        let span = max(preferences.blurSpan, 1)
        let startAngle = effectStartAngle ?? effectiveStartAngle
        return min(max((startAngle - angle) / span, 0), 1)
    }

    private var effectiveStartAngle: Double {
        TriggerAnglePolicy.resolvedStartAngle(
            manualAngle: preferences.thresholdAngle,
            learnedAngle: preferences.learnedTriggerAngle,
            adaptiveEnabled: preferences.isAdaptiveTriggerAngleEnabled,
            adaptiveOffset: preferences.adaptiveTriggerAngleOffset
        )
    }

    // MARK: - Animation

    private func startDisplayLink() {
        stopDisplayLink()
        guard let link = overlay.makeDisplayLink(delegate: self) else {
            Diagnostics.lid.notice("display link skipped, no overlay window")
            return
        }
        Diagnostics.lid.notice("display link started")
        link.preferredFrameRateRange = CAFrameRateRange(
            minimum: Self.targetFramesPerSecond,
            maximum: Self.targetFramesPerSecond,
            preferred: Self.targetFramesPerSecond
        )
        // One frame is enough for this lightweight pass and keeps the lid
        // motion from visibly trailing the physical screen.
        link.preferredFrameLatency = 1
        link.add(to: .main, forMode: .common)
        lastFrameTime = 0
        displayFrameCount = 0
        submittedDisplayFrameCount = 0
        firstDisplayFrameTime = nil
        slowDisplayFrameCount = 0
        longestDisplayFrameInterval = 0
        slowDisplayWorkCount = 0
        longestDisplayWorkDuration = 0
        displayLink = link
    }

    private func stopDisplayLink() {
        if displayFrameCount > 1, let firstDisplayFrameTime, lastFrameTime > firstDisplayFrameTime {
            let duration = lastFrameTime - firstDisplayFrameTime
            let fps = Double(displayFrameCount - 1) / duration
            let submittedFPS = submittedDisplayFrameCount > 1
                ? Double(submittedDisplayFrameCount - 1) / duration
                : 0
            Diagnostics.lid.notice(
                "display link stopped after \(self.displayFrameCount) callbacks at \(fps, format: .fixed(precision: 1)) fps; submitted \(self.submittedDisplayFrameCount) frames at \(submittedFPS, format: .fixed(precision: 1)) fps; slow callbacks \(self.slowDisplayFrameCount), longest interval \(self.longestDisplayFrameInterval * 1000, format: .fixed(precision: 1)) ms; slow work \(self.slowDisplayWorkCount), longest work \(self.longestDisplayWorkDuration * 1000, format: .fixed(precision: 1)) ms"
            )
        }
        displayLink?.invalidate()
        displayLink = nil
        lastFrameTime = 0
        displayFrameCount = 0
        submittedDisplayFrameCount = 0
        firstDisplayFrameTime = nil
        slowDisplayFrameCount = 0
        longestDisplayFrameInterval = 0
        slowDisplayWorkCount = 0
        longestDisplayWorkDuration = 0
    }

    func metalDisplayLink(_ link: CAMetalDisplayLink, needsUpdate update: CAMetalDisplayLink.Update) {
        let now = CACurrentMediaTime()
        if firstDisplayFrameTime == nil { firstDisplayFrameTime = now }
        let rawInterval = lastFrameTime > 0 ? now - lastFrameTime : 1.0 / Double(Self.targetFramesPerSecond)
        let dt = min(max(rawInterval, 1.0 / 240), 1.0 / 20)
        lastFrameTime = now
        displayFrameCount &+= 1
        longestDisplayFrameInterval = max(longestDisplayFrameInterval, rawInterval)
        if rawInterval > Self.slowDisplayFrameInterval { slowDisplayFrameCount &+= 1 }
        if let frame = streamer.newFrame() {
            overlay.absorb(frame)
        }
        visualAngle.advance(to: rawAngle, dt: dt)
        if applyVisual(angle: visualAngle.value, drawable: update.drawable) {
            submittedDisplayFrameCount &+= 1
        }
        let workDuration = CACurrentMediaTime() - now
        longestDisplayWorkDuration = max(longestDisplayWorkDuration, workDuration)
        if workDuration > Self.slowDisplayWorkDuration { slowDisplayWorkCount &+= 1 }
    }

    /// The geometry takes the lid angle itself, so only the blur saturates.
    private func applyVisual(angle: Double, drawable: any CAMetalDrawable) -> Bool {
        let progress = blurProgress(for: angle)
        return overlay.update(
            progress: progress,
            currentAngle: angle,
            tuning: tuning,
            drawable: drawable
        )
    }

    private var tuning: DepthTuning {
        DepthTuning(
            viewingDistance: preferences.viewingDistance,
            recession: preferences.recession,
            blurEvenness: preferences.blurEvenness,
            dimReach: preferences.dimReach,
            maxBlurRadius: preferences.maxBlurRadius,
            maxDim: preferences.maxDim
        )
    }

    // MARK: - System events

    private func observeSystemEvents() {
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.suspend() }
        }
        workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.resume() }
        }
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                // macOS posts this for backlight and colour changes too.
                let screen = NSScreen.builtIn
                let layout = Layout(displayID: screen?.displayID, frame: screen?.frame)
                guard layout != self.builtInLayout else {
                    Diagnostics.lid.notice("screen parameters changed, layout unchanged")
                    return
                }
                Diagnostics.lid.notice(
                    "screen parameters changed, layout now \(String(describing: layout), privacy: .public)"
                )
                self.builtInLayout = layout
                if self.isActive { self.setActive(false) }
                self.streamer.stop()
                self.streamer.invalidateFilter()
                Task { await self.streamer.warmFilter() }
                self.overlay.discardLive()
                self.snapshotter.discard()
                Task { await self.snapshotter.warmFilter() }
            }
        }
    }

    private func suspend() {
        Diagnostics.lid.notice("suspend")
        isSuspended = true
        stopDisplayLink()
        overlay.dismiss(animated: false)
        snapshotter.endPrewarm()
        snapshotter.discard()
        streamer.stop()
        overlay.discardLive()
        preview = nil
        isActive = false
        isCapturePending = false
        effectStartAngle = nil
        adaptiveAngleTracker.reset()
    }

    private func resume() {
        Diagnostics.lid.notice("resume")
        isSuspended = false
        // A fresh baseline, so waking with a nearly shut lid does not read as
        // closing movement.
        lastChangedAngle = nil
        angularVelocity = 0
        lastClosingTime = -.greatestFiniteMagnitude
        lastMovedDownTime = -.greatestFiniteMagnitude
        lastMeaningfulMotionTime = -.greatestFiniteMagnitude
        adaptiveAngleTracker.reset()
        setPollInterval(Self.idlePollInterval)
        poll()
    }
}
