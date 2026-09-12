import AppKit
import CoreVideo
import Metal
import ScreenCaptureKit

/// A live picture of the built-in display, handed over as Metal textures.
///
/// Frames are `IOSurface` backed, so wrapping one as a texture copies nothing.
/// `startCapture` takes long enough that the stream has to be started while
/// the lid is still closing rather than at the trigger angle.
@MainActor
final class ScreenStreamer {

    /// Display P3 carries the same transfer function as sRGB, so the shader's
    /// sRGB pixel format decodes it correctly.
    static let colourSpaceName = CGColorSpace.displayP3

    /// Full Retina capture makes the live Gaussian pyramid miss the 60 Hz
    /// frame budget. Three-quarter Retina stays sharp during motion while
    /// leaving enough GPU time for every display refresh. Still captures keep
    /// their full backing scale.
    static let maximumLivePixelScale: CGFloat = 1.5

    static func livePixelScale(for screen: NSScreen) -> CGFloat {
        min(screen.backingScaleFactor, maximumLivePixelScale)
    }

    /// Frames arrive on the stream's own queue. The newest one is kept under a
    /// lock and picked up on the main thread; the texture cache is only ever
    /// touched from the stream queue.
    private final class Receiver: NSObject, SCStreamOutput {
        private let cache: CVMetalTextureCache
        private let lock = NSLock()
        private var newest: CVMetalTexture?
        private var newestID: UInt64 = 0
        private var firstFrameTime: CFTimeInterval?
        private var lastFrameTime: CFTimeInterval?

        init?(device: MTLDevice) {
            var made: CVMetalTextureCache?
            guard CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &made) == kCVReturnSuccess,
                  let made else { return nil }
            cache = made
            super.init()
        }

        /// The newest frame and its number, or `nil` before the first one.
        func latest() -> (texture: MTLTexture, id: UInt64)? {
            lock.lock()
            defer { lock.unlock() }
            guard let newest, let texture = CVMetalTextureGetTexture(newest) else { return nil }
            return (texture, newestID)
        }

        /// Capture cadence measured at the stream callback, before frames are
        /// reduced to the newest one for rendering.
        func statistics() -> (frames: UInt64, duration: TimeInterval, fps: Double)? {
            lock.lock()
            defer { lock.unlock() }
            guard newestID > 1, let firstFrameTime, let lastFrameTime,
                  lastFrameTime > firstFrameTime else { return nil }
            let duration = lastFrameTime - firstFrameTime
            return (newestID, duration, Double(newestID - 1) / duration)
        }

        func stream(
            _ stream: SCStream,
            didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
            of type: SCStreamOutputType
        ) {
            guard type == .screen,
                  CMSampleBufferIsValid(sampleBuffer),
                  let pixels = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

            var wrapped: CVMetalTexture?
            let result = CVMetalTextureCacheCreateTextureFromImage(
                kCFAllocatorDefault,
                cache,
                pixels,
                nil,
                .bgra8Unorm_srgb,
                CVPixelBufferGetWidth(pixels),
                CVPixelBufferGetHeight(pixels),
                0,
                &wrapped
            )
            guard result == kCVReturnSuccess, let wrapped else { return }

            lock.lock()
            let now = CACurrentMediaTime()
            if firstFrameTime == nil { firstFrameTime = now }
            lastFrameTime = now
            newest = wrapped
            newestID &+= 1
            lock.unlock()
        }
    }

    private let device: MTLDevice?
    private var stream: SCStream?
    private var receiver: Receiver?
    private var startTask: Task<Void, Never>?
    /// Enumerating every on screen window costs about 70 ms, so the filter is
    /// kept between runs and rebuilt only when the display changes.
    private var filter: SCContentFilter?
    private var filterDisplayID: CGDirectDisplayID?
    private var consumedID: UInt64 = 0
    private var handedOverFrames: UInt64 = 0
    private var firstHandOverTime: CFTimeInterval?
    private var lastHandOverTime: CFTimeInterval?

    private(set) var isStarted = false
    private(set) var screen: NSScreen?

    init(device: MTLDevice? = MTLCreateSystemDefaultDevice()) {
        self.device = device
    }

    /// Begins capturing, or does nothing if it is already running.
    func start() {
        guard !isStarted, startTask == nil, device != nil else { return }
        guard let target = NSScreen.builtIn, let displayID = target.displayID else { return }
        screen = target
        isStarted = true
        startTask = Task { [weak self] in
            await self?.begin(displayID: displayID, on: target)
            self?.startTask = nil
        }
    }

    func stop() {
        guard isStarted || stream != nil else { return }
        isStarted = false
        startTask?.cancel()
        startTask = nil
        let closing = stream
        if let statistics = receiver?.statistics() {
            Diagnostics.geometry.notice(
                "stream received \(statistics.frames) frames at \(statistics.fps, format: .fixed(precision: 1)) fps over \(statistics.duration, format: .fixed(precision: 2)) s"
            )
        }
        if handedOverFrames > 1, let firstHandOverTime, let lastHandOverTime,
           lastHandOverTime > firstHandOverTime {
            let duration = lastHandOverTime - firstHandOverTime
            let fps = Double(handedOverFrames - 1) / duration
            Diagnostics.geometry.notice(
                "stream handed over \(self.handedOverFrames) frames at \(fps, format: .fixed(precision: 1)) fps over \(duration, format: .fixed(precision: 2)) s"
            )
        }
        stream = nil
        receiver = nil
        consumedID = 0
        handedOverFrames = 0
        firstHandOverTime = nil
        lastHandOverTime = nil
        Diagnostics.geometry.notice("stream stopped")
        guard let closing else { return }
        Task { try? await closing.stopCapture() }
    }

    /// Builds the capture filter without starting anything.
    func warmFilter() async {
        guard let displayID = NSScreen.builtIn?.displayID else { return }
        guard filter == nil || filterDisplayID != displayID else { return }
        await rebuildFilter(displayID: displayID)
    }

    /// Drops the cached filter, so the next start enumerates the windows again.
    func invalidateFilter() {
        filter = nil
        filterDisplayID = nil
    }

    /// The newest frame, but only once. `nil` when nothing new has arrived
    /// since the last call.
    func newFrame() -> MTLTexture? {
        guard let latest = receiver?.latest(), latest.id != consumedID else { return nil }
        consumedID = latest.id
        let now = CACurrentMediaTime()
        if firstHandOverTime == nil { firstHandOverTime = now }
        lastHandOverTime = now
        handedOverFrames &+= 1
        return latest.texture
    }

    private func begin(displayID: CGDirectDisplayID, on target: NSScreen) async {
        guard let device, let receiver = Receiver(device: device) else {
            isStarted = false
            return
        }
        do {
            if filter == nil || filterDisplayID != displayID {
                await rebuildFilter(displayID: displayID)
            }
            guard isStarted, let activeFilter = filter else { return }

            let configuration = SCStreamConfiguration()
            let pixelScale = min(CGFloat(activeFilter.pointPixelScale), Self.maximumLivePixelScale)
            configuration.width = Int((activeFilter.contentRect.width * pixelScale).rounded())
            configuration.height = Int((activeFilter.contentRect.height * pixelScale).rounded())
            configuration.minimumFrameInterval = CMTime(value: 1, timescale: 60)
            configuration.pixelFormat = kCVPixelFormatType_32BGRA
            configuration.colorSpaceName = Self.colourSpaceName
            configuration.showsCursor = false
            configuration.queueDepth = 3
            configuration.scalesToFit = false

            let fresh = SCStream(filter: activeFilter, configuration: configuration, delegate: nil)
            try fresh.addStreamOutput(
                receiver,
                type: .screen,
                sampleHandlerQueue: DispatchQueue(label: "MacDuo.frames", qos: .userInteractive)
            )
            let started = CFAbsoluteTimeGetCurrent()
            try await fresh.startCapture()
            guard isStarted else {
                try? await fresh.stopCapture()
                return
            }
            self.receiver = receiver
            self.stream = fresh
            self.screen = target
            Diagnostics.geometry.notice(
                """
                stream started \(configuration.width)x\(configuration.height) px in \
                \((CFAbsoluteTimeGetCurrent() - started) * 1000, format: .fixed(precision: 1)) ms
                """
            )
        } catch {
            Diagnostics.geometry.error("stream failed: \(String(describing: error), privacy: .public)")
            invalidateFilter()
            isStarted = false
        }
    }

    private func rebuildFilter(displayID: CGDirectDisplayID) async {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: true
            )
            guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
                invalidateFilter()
                return
            }
            // Exclude ourselves, or the overlay feeds back into its own picture.
            let bundleID = Bundle.main.bundleIdentifier
            let ownApplications = content.applications.filter { $0.bundleIdentifier == bundleID }
            if ownApplications.isEmpty {
                Diagnostics.geometry.error("stream cannot exclude this app: it owns no window yet")
            }
            filter = SCContentFilter(
                display: display,
                excludingApplications: ownApplications,
                exceptingWindows: []
            )
            filterDisplayID = displayID
        } catch {
            Diagnostics.geometry.error("stream filter failed: \(String(describing: error), privacy: .public)")
            invalidateFilter()
        }
    }
}
