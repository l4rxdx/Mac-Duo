import AppKit
import CoreGraphics
import ImageIO

/// Provides only privacy-safe pixels for the lock screen. It reads the user's
/// wallpaper file and never asks ScreenCaptureKit for desktop or login-window
/// contents. A neutral gradient is always available as an immediate fallback.
enum LockScreenBackground {
    @MainActor
    static func wallpaperURL(for screen: NSScreen) -> URL? {
        NSWorkspace.shared.desktopImageURL(for: screen)
    }

    nonisolated static func loadWallpaper(at url: URL, maximumPixelSize: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(maximumPixelSize, 1),
            kCGImageSourceShouldCacheImmediately: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    nonisolated static func fallbackImage() -> CGImage? {
        let width = 64
        let height = 64
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        let colours = [
            CGColor(red: 0.055, green: 0.07, blue: 0.11, alpha: 1),
            CGColor(red: 0.012, green: 0.016, blue: 0.028, alpha: 1),
        ] as CFArray
        guard let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: colours,
            locations: [0, 1]
        ) else { return nil }
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: width / 2, y: height),
            end: CGPoint(x: width / 2, y: 0),
            options: []
        )
        return context.makeImage()
    }
}
