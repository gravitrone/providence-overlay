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

    init(state: AppState) {
        self.state = state
        wireAppSwitchObservers()
        startIdleTimer()
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
        Logger.log("scheduler: transition \(mode.rawValue) -> \(newMode.rawValue)")
        mode = newMode
        fps = fpsFor(newMode)
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
            .sink { [weak self] _ in
                Task { @MainActor in self?.markActive() }
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
        if mode == .burst && Date() > burstUntil {
            transitionTo(activityMode())
            return
        }
        transitionTo(activityMode())
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
