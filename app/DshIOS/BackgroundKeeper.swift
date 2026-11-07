import AVFoundation
import BackgroundTasks
import SwiftUI
import UIKit

/// Keeps the engine running while the app is off screen. iOS suspends the whole
/// process shortly after the app leaves the screen, and with it Node: agent
/// turns, automations and dev servers all freeze until the app comes back.
///
/// - Always: a UIKit background task gives in-flight turns the usual ~30 s
///   grace, ended early once nothing is running.
/// - The 设置 → 后台运行 →「静音音频」switch (on by default): silent, mixable audio keeps the
///   process alive for as long as it stays in the background (the `audio`
///   background mode), so automations and dev servers keep going too. It is an
///   indirect means, hence the user-facing switch.
/// - The 设置 → 后台运行 →「任务续跑」switch (iOS 26+, off by default): a
///   a system grace period when the app leaves the screen with sessions
///   running, so a turn can finish off screen; the system shows its progress and
///   the user can stop it there. Not submitted for work the user watches to the end.
@MainActor
final class BackgroundKeeper {
    static let shared = BackgroundKeeper()
    static let enabledKey = "backgroundKeepAlive"
    /// Matches `BGTaskSchedulerPermittedIdentifiers` in project.yml.
    private static let taskPrefix = (Bundle.main.bundleIdentifier ?? "com.wsw.dsh-ios") + ".task"

    /// Silent audio.
    var enabled: Bool { UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true }

    private var inBackground = false
    private var running: [String] = []
    /// Re-reads the session list; set by the current engine connection.
    private var refresh: (() async -> Void)?
    private var grace: UIBackgroundTaskIdentifier = .invalid
    private var pollTask: Task<Void, Never>?
    private let audio = SilentAudio()

    private init() {}

    func attach(refresh: @escaping () async -> Void) {
        self.refresh = refresh
    }

    /// The titles of running sessions, after every session-list refresh. Each
    /// refresh follows engine activity, so while busy it also counts as progress.
    func update(running titles: [String]) {
        running = titles
        if titles.isEmpty {
            if inBackground && !enabled { endGrace() }
            return
        }
    }

    /// A switch changed; while off screen it takes effect at once.
    func settingsChanged() {
        guard inBackground else { return }
        if enabled { audio.start() } else { audio.stop() }
    }

    func scenePhaseChanged(to phase: ScenePhase) {
        switch phase {
        case .active:
            inBackground = false
            pollTask?.cancel()
            audio.stop()
            endGrace()
        case .background:
            guard !inBackground else { return }
            inBackground = true
            beginGrace()
            if enabled { audio.start() }
            poll()
        default:
            // Still in the foreground: refresh for work the cached list missed
            // (an automation, a session not on screen).
            Task { await refresh?() }
        }
    }

    // MARK: Grace period

    private func beginGrace() {
        guard grace == .invalid else { return }
        grace = UIApplication.shared.beginBackgroundTask(withName: "dsh-engine") { [weak self] in
            MainActor.assumeIsolated { self?.endGrace() }
        }
    }

    private func endGrace() {
        guard grace != .invalid else { return }
        UIApplication.shared.endBackgroundTask(grace)
        grace = .invalid
    }

    /// Off screen no view drives refreshes; ask the engine directly.
    private func poll() {
        pollTask?.cancel()
        pollTask = Task {
            while !Task.isCancelled {
                await refresh?()
                try? await Task.sleep(for: .seconds(10))
            }
        }
    }

}

/// Plays silence through a mixable `.playback` session: the app keeps running
/// in the background without taking over the user's audio or Now Playing.
@MainActor
private final class SilentAudio {
    private var engine: AVAudioEngine?
    private var observers: [NSObjectProtocol] = []

    func start() {
        guard engine == nil else { return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
            let engine = AVAudioEngine()
            let player = AVAudioPlayerNode()
            let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 44_100)!
            buffer.frameLength = buffer.frameCapacity
            memset(buffer.floatChannelData![0], 0, Int(buffer.frameLength) * MemoryLayout<Float>.size)
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
            try engine.start()
            player.scheduleBuffer(buffer, at: nil, options: .loops)
            player.play()
            self.engine = engine
        } catch {
            print("[keepalive] silent audio failed: \(error)")
            return
        }
        // A call or another app's non-mixable audio stops the engine; resume after it.
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
                let ended = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt) == AVAudioSession.InterruptionType.ended.rawValue
                if ended { MainActor.assumeIsolated { self?.restart() } }
            },
            center.addObserver(forName: .AVAudioEngineConfigurationChange, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.restart() }
            },
        ]
    }

    func stop() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        guard let engine else { return }
        engine.stop()
        self.engine = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func restart() {
        guard engine != nil else { return }
        stop()
        start()
    }
}
