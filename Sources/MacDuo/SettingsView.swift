import AppKit
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @ObservedObject var preferences: Preferences
    @ObservedObject var controller: LidController

    @State private var launchesAtLogin = SMAppService.mainApp.status == .enabled
    @State private var hasScreenPermission = CGPreflightScreenCaptureAccess()
    @State private var settingsOpenFailed = false

    var onQuit: () -> Void

    private static let width: CGFloat = 300
    private static let inset: CGFloat = 14
    private static let bodyHeight: CGFloat = 400
    private static let authorURL = URL(string: "https://github.com/sumimakito")!
    private static let screenRecordingSettingsURL = URL(
        string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ScreenCapture"
    )!

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, Self.inset)
                .padding(.top, 12)
                .padding(.bottom, 10)
            Divider()
            if controller.isSensorAvailable {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        switches
                        if !hasScreenPermission {
                            permissionNotice
                        }
                        startGroup
                        lookGroup
                        perspectiveGroup
                    }
                    .padding(.horizontal, Self.inset)
                    .padding(.vertical, 10)
                }
                .frame(height: Self.bodyHeight)
            } else {
                unavailableNotice
                    .padding(.horizontal, Self.inset)
                    .padding(.vertical, 12)
            }
            Divider()
            appGroup
                .padding(.horizontal, Self.inset)
                .padding(.top, 10)
                .padding(.bottom, 12)
        }
        .frame(width: Self.width)
        .onAppear { hasScreenPermission = CGPreflightScreenCaptureAccess() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            hasScreenPermission = CGPreflightScreenCaptureAccess()
        }
        .environment(\.locale, preferences.interfaceLanguage.locale)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Mac Duo").font(.title2.weight(.semibold))
            Spacer()
            Text(String(format: "%.1f°", controller.currentAngle))
                .font(.system(.title3, design: .rounded).monospacedDigit())
                .foregroundStyle(.secondary)
                .accessibilityLabel("Lid angle")
        }
    }

    private var unavailableNotice: some View {
        Text("This Mac has no lid angle sensor. Only some MacBook models have one.")
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var switches: some View {
        VStack(alignment: .leading, spacing: 4) {
            toggleRow(
                "Depth effect",
                isOn: $preferences.isEnabled,
                help: "Leans the screen away as the lid closes."
            )
            toggleRow(
                "Live rendering",
                isOn: $preferences.isLivePicture,
                help: "Off holds the frame from when the effect started."
            )
            .disabled(!preferences.isEnabled)
        }
    }

    private var startGroup: some View {
        group("Start") {
            toggleRow(
                "Adaptive trigger angle",
                isOn: $preferences.isAdaptiveTriggerAngleEnabled,
                help: nil
            )
            slider(
                "Angle learning time", value: $preferences.adaptiveLearningDuration,
                in: 5...60, format: "%.0f s", step: 1
            )
            .disabled(!preferences.isAdaptiveTriggerAngleEnabled)
            slider(
                "Accidental trigger buffer", value: $preferences.adaptiveTriggerAngleOffset,
                in: TriggerAnglePolicy.adaptiveBufferRange, format: "%.0f°", step: 1,
                help: "How much farther the lid must close before the effect starts."
            )
            .disabled(!preferences.isAdaptiveTriggerAngleEnabled)
            slider(
                "Start angle", value: displayedStartAngle, in: 5...130, format: "%.0f°",
                help: "The effect starts at this angle."
            )
            .disabled(preferences.isAdaptiveTriggerAngleEnabled)
            slider(
                "Full effect after", value: $preferences.blurSpan, in: 5...60, format: "%.0f°",
                help: "Degrees of further closing to reach full strength."
            )
        }
    }

    private var lookGroup: some View {
        group("Look") {
            slider(
                "Blur", value: $preferences.maxBlurRadius, in: 10...160, format: "%.0f pt",
                help: "Blur radius at the far edge."
            )
            slider(
                "Blur spread", value: $preferences.blurEvenness, in: 0...1, format: "%.0f%%", scale: 100,
                help: "0 blurs the far edge only, 100 the whole picture."
            )
            slider(
                "Dimming", value: $preferences.maxDim, in: 0...1, format: "%.0f%%", scale: 100,
                help: "How dark the far edge goes."
            )
            slider(
                "Dimming spread", value: $preferences.dimReach, in: 0.2...1, format: "%.0f%%", scale: 100,
                help: "Everything above this height goes fully dark."
            )
        }
    }

    private var perspectiveGroup: some View {
        group("Perspective") {
            slider(
                "Lean back", value: $preferences.recession, in: 0...3, format: "%.1f×",
                help: "Degrees of lean per degree of closing. 1 holds it still."
            )
            slider(
                "Perspective", value: perspective, in: 0...1, format: "%.0f%%", scale: 100,
                help: "0 keeps the sides parallel, 100 converges sharply."
            )
        }
    }

    private var appGroup: some View {
        VStack(alignment: .leading, spacing: 8) {
            languagePicker
            toggleRow("Show angle in menu bar", isOn: $preferences.showsAngleInMenuBar, help: nil)
            toggleRow("Launch at login", isOn: $launchesAtLogin, help: nil)
                .onChange(of: launchesAtLogin) { _, newValue in
                    setLaunchAtLogin(newValue)
                }
            HStack {
                Button("Reset") { preferences.resetToDefaults() }
                Spacer()
                Button("Quit", action: onQuit)
            }
            .controlSize(.small)
            .padding(.top, 2)
            HStack(spacing: 0) {
                Text("Made by ").foregroundStyle(.secondary)
                Link("Makito", destination: Self.authorURL)
                    .pointingHand()
                Spacer()
                Text("© 2026 Makito").foregroundStyle(.secondary)
            }
            .font(.caption2)
            .padding(.top, 2)
        }
    }

    private var languagePicker: some View {
        HStack {
            Text("Language")
            Spacer()
            Picker("Language", selection: $preferences.interfaceLanguage) {
                ForEach(Preferences.InterfaceLanguage.allCases) { language in
                    languageLabel(language)
                        .tag(language)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .controlSize(.small)
            .fixedSize()
            .accessibilityLabel("Language")
        }
    }

    @ViewBuilder
    private func languageLabel(_ language: Preferences.InterfaceLanguage) -> some View {
        switch language {
        case .system:
            Text("Follow System")
        case .simplifiedChinese:
            Text("Simplified Chinese")
        case .english:
            Text("English")
        }
    }

    private func toggleRow(
        _ title: LocalizedStringKey,
        isOn: Binding<Bool>,
        help: LocalizedStringKey?
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                Spacer()
                Toggle("", isOn: isOn)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .accessibilityLabel(Text(title))
            }
            description(help)
        }
    }

    @ViewBuilder
    private func description(_ text: LocalizedStringKey?) -> some View {
        if let text {
            Text(text)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var perspective: Binding<Double> {
        Binding(
            get: { (Preferences.farthestEye - preferences.viewingDistance) / Preferences.eyeRange },
            set: { preferences.viewingDistance = Preferences.farthestEye - $0 * Preferences.eyeRange }
        )
    }

    private var displayedStartAngle: Binding<Double> {
        Binding(
            get: {
                TriggerAnglePolicy.resolvedStartAngle(
                    manualAngle: preferences.thresholdAngle,
                    learnedAngle: preferences.learnedTriggerAngle,
                    adaptiveEnabled: preferences.isAdaptiveTriggerAngleEnabled,
                    adaptiveOffset: preferences.adaptiveTriggerAngleOffset
                )
            },
            set: { preferences.thresholdAngle = $0 }
        )
    }

    private var permissionNotice: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Screen Recording permission is required to show the depth effect.")
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            Button("Open System Settings") {
                openScreenRecordingSettings()
            }
            .controlSize(.small)
            if settingsOpenFailed {
                Text("Could not open System Settings. Open it manually and enable screen recording for Mac Duo under Privacy & Security.")
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }

    private func openScreenRecordingSettings() {
        settingsOpenFailed = false
        Task { @MainActor in
            do {
                let configuration = NSWorkspace.OpenConfiguration()
                configuration.activates = true
                _ = try await NSWorkspace.shared.open(Self.screenRecordingSettingsURL, configuration: configuration)
            } catch {
                settingsOpenFailed = true
            }
        }
    }

    private func group<Content: View>(
        _ title: LocalizedStringKey,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
        }
        .disabled(!preferences.isEnabled)
    }

    private func slider(
        _ title: LocalizedStringKey,
        value: Binding<Double>,
        in range: ClosedRange<Double>,
        format: String,
        scale: Double = 1,
        step: Double? = nil,
        help: LocalizedStringKey? = nil
    ) -> some View {
        let reading = String(format: format, value.wrappedValue * scale)
        return VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                Spacer()
                Text(reading)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            if let step {
                Slider(value: value, in: range, step: step)
                    .labelsHidden()
                    .controlSize(.small)
                    .accessibilityLabel(Text(title))
                    .accessibilityValue(reading)
            } else {
                Slider(value: value, in: range)
                    .labelsHidden()
                    .controlSize(.small)
                    .accessibilityLabel(Text(title))
                    .accessibilityValue(reading)
            }
            description(help)
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            launchesAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}

private extension View {
    func pointingHand() -> some View {
        modifier(PointingHand())
    }
}

private struct PointingHand: ViewModifier {
    @State private var pushed = false

    func body(content: Content) -> some View {
        content
            .onHover { inside in
                if inside, !pushed {
                    NSCursor.pointingHand.push()
                    pushed = true
                } else if !inside, pushed {
                    NSCursor.pop()
                    pushed = false
                }
            }
            .onDisappear {
                if pushed {
                    NSCursor.pop()
                    pushed = false
                }
            }
    }
}
