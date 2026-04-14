import Foundation
import AppKit
import Combine

enum CaptureMode: String {
    case idle     // 0.2 fps - no activity detected
    case active   // 1 fps - user typing or scrolling
    case meeting  // 2 fps - video call detected
    case burst    // 5 fps - user just said wake word or hit hotkey
}

@MainActor
final class AdaptiveScheduler: ObservableObject {
    @Published private(set) var mode: CaptureMode = .idle
    @Published private(set) var fps: Double = 0.2

    private let state: AppState
    private var lastActivityAt: Date = .distantPast
    private var burstUntil: Date = .distantPast
    private var cancellables = Set<AnyCancellable>()
    private var idleTimer: Timer?

    // Phase 10: battery-aware downgrade. Hysteresis: downgrade at <20%,
    // restore only once charging or level >= 25%.
    private var batteryForcedIdle: Bool = false

    init(state: AppState) {
        self.state = state
        wireAppSwitchObservers()
        startIdleTimer()
        Logger.log("scheduler: installed, initial mode=\(mode.rawValue) fps=\(fps)")
        // Kick an initial evaluation so the @Published fps emits a fresh value
        // and any frontmost-app state is captured at launch.
        markActive()
    }

    deinit {
        idleTimer?.invalidate()
    }

    func markActive() {
        lastActivityAt = Date()
        transitionTo(activityMode())
    }

    func beginBurst(duration: TimeInterval = 3) {
        burstUntil = Date().addingTimeInterval(duration)
        transitionTo(.burst)
    }

    func markMeetingDetected() { transitionTo(.meeting) }
    func markMeetingEnded() { transitionTo(activityMode()) }

    private func activityMode() -> CaptureMode {
        if let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
           MeetingApps.contains(bundleID) {
            return .meeting
        }
        return Date().timeIntervalSince(lastActivityAt) < 30 ? .active : .idle
    }

    private func transitionTo(_ newMode: CaptureMode) {
        if mode == newMode { return }
        let oldMode = mode
        let newFps = fpsFor(newMode)
        Logger.log("scheduler: marked active, transition=\(oldMode.rawValue)->\(newMode.rawValue) fps=\(newFps)")
        mode = newMode
        fps = newFps
    }

    private func fpsFor(_ mode: CaptureMode) -> Double {
        switch mode {
        case .idle: return 0.2
        case .active: return 1
        case .meeting: return 2
        case .burst: return 5
        }
    }

    private func wireAppSwitchObservers() {
        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.didActivateApplicationNotification)
            .sink { [weak self] note in
                let bundleID = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?
                    .bundleIdentifier ?? "?"
                Task { @MainActor in
                    Logger.log("scheduler: workspace activation, bundle=\(bundleID)")
                    self?.markActive()
                }
            }
            .store(in: &cancellables)
    }

    private func startIdleTimer() {
        idleTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.evaluate() }
        }
    }

    @MainActor
    private func evaluate() {
        checkBatteryAndMaybeDowngrade()
        if batteryForcedIdle {
            if mode != .idle { transitionTo(.idle) }
            return
        }
        if mode == .burst && Date() > burstUntil {
            transitionTo(activityMode())
            return
        }
        transitionTo(activityMode())
    }

    /// Phase 10: force idle mode + disable wake word when on battery < 20%.
    /// Restore when charging or level climbs to 25% (hysteresis prevents flapping).
    private func checkBatteryAndMaybeDowngrade() {
        let status = BatteryMonitor.current()
        state.batteryLevel = status.level
        state.onBattery = status.onBattery

        if batteryForcedIdle {
            // Restore only once off battery or level >= 25%.
            if !status.onBattery || status.level >= 0.25 {
                batteryForcedIdle = false
                state.wakeWordAllowed = true
                Logger.log("scheduler: battery restored (onBattery=\(status.onBattery) level=\(status.level))")
            }
        } else {
            if status.onBattery && status.level < 0.20 {
                batteryForcedIdle = true
                state.wakeWordAllowed = false
                Logger.log("scheduler: battery low (\(Int(status.level * 100))%) - forcing idle, wake word off")
            }
        }
    }
}

private enum MeetingApps {
    static let bundleIDs: Set<String> = [
        "us.zoom.xos",
        "com.microsoft.teams",
        "com.hnc.Discord",
        "com.apple.FaceTime",
    ]
    static func contains(_ id: String) -> Bool { bundleIDs.contains(id) }
}
