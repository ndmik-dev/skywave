import Foundation
import Network

#if canImport(AppKit)
import AppKit
#endif

public enum ReconnectReason: String, Sendable {
    /// The machine woke up; a stream socket rarely survives sleep.
    case wake
    /// The network came back after being unreachable.
    case networkReturned
    case stalled
    case failed
    /// Nothing failed outright, but playback never resumed either.
    case watchdog
}

/// Watches for the things that quietly kill a long-running stream and asks for a
/// reconnect, backing off so a station that is genuinely down is not hammered.
///
/// It holds no player of its own — it only observes and signals.
@MainActor
public final class Resilience {
    /// Called with the reason and how many attempts have failed in a row since
    /// playback was last confirmed.
    public var onReconnect: ((ReconnectReason, Int) -> Void)?

    /// Injectable so the checks can exercise the same logic in milliseconds.
    public struct Policy: Sendable {
        /// Rises while reconnects keep failing, resets once playback is confirmed.
        public var backoff: [Duration]
        /// How long playback may stay stopped, while a station is selected,
        /// before the watchdog treats it as stuck.
        public var watchdogGrace: Duration
        public var watchdogPoll: Duration

        public init(
            backoff: [Duration] = [.seconds(2), .seconds(5), .seconds(10), .seconds(20), .seconds(30)],
            watchdogGrace: Duration = .seconds(25),
            watchdogPoll: Duration = .seconds(5)
        ) {
            self.backoff = backoff
            self.watchdogGrace = watchdogGrace
            self.watchdogPoll = watchdogPoll
        }
    }

    private let policy: Policy

    /// True between a play request and an explicit stop.
    private var isWanted = false
    private var isPlaying = false
    private var attempt = 0
    private var notPlayingSince: ContinuousClock.Instant?

    private var tasks: [Task<Void, Never>] = []
    private var pendingReconnect: Task<Void, Never>?
    private var monitor: NWPathMonitor?
    private var wasNetworkSatisfied = true

    public init(policy: Policy = Policy()) {
        self.policy = policy
    }

    public func start() {
        guard tasks.isEmpty else { return }

        #if canImport(AppKit)
        let wakes = NSWorkspace.shared.notificationCenter
            .notifications(named: NSWorkspace.didWakeNotification)
        tasks.append(Task { [weak self] in
            for await _ in wakes { self?.reconnect(.wake) }
        })
        #endif

        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            let satisfied = path.status == .satisfied
            Task { @MainActor in self?.networkChanged(satisfied: satisfied) }
        }
        monitor.start(queue: DispatchQueue(label: "skywave.path"))
        self.monitor = monitor

        tasks.append(Task { [weak self] in await self?.watchdogLoop() })
    }

    public func stop() {
        tasks.forEach { $0.cancel() }
        tasks.removeAll()
        pendingReconnect?.cancel()
        pendingReconnect = nil
        monitor?.cancel()
        monitor = nil
    }

    // MARK: - Playback state

    /// A station was requested. Reconnects are armed from here until `noteStopped`.
    public func noteStarted() {
        isWanted = true
        isPlaying = false
        notPlayingSince = ContinuousClock.now
    }

    public func notePlaying() {
        isPlaying = true
        notPlayingSince = nil
        // Playback is proven, so the next failure starts from the shortest delay.
        attempt = 0
    }

    public func notePaused() {
        guard isWanted, isPlaying else { return }
        isPlaying = false
        notPlayingSince = ContinuousClock.now
    }

    public func noteStalled() { reconnect(.stalled) }

    public func noteFailed() { reconnect(.failed) }

    public func noteStopped() {
        isWanted = false
        isPlaying = false
        notPlayingSince = nil
        attempt = 0
        pendingReconnect?.cancel()
        pendingReconnect = nil
    }

    // MARK: - Triggers

    private func networkChanged(satisfied: Bool) {
        defer { wasNetworkSatisfied = satisfied }
        // Only the return matters; the loss already shows up as a stall.
        guard satisfied, !wasNetworkSatisfied else { return }
        reconnect(.networkReturned)
    }

    private func watchdogLoop() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: policy.watchdogPoll)
            guard !Task.isCancelled, isWanted, !isPlaying,
                  let since = notPlayingSince,
                  ContinuousClock.now - since > policy.watchdogGrace else { continue }
            reconnect(.watchdog)
        }
    }

    private func reconnect(_ reason: ReconnectReason) {
        guard isWanted, pendingReconnect == nil else { return }
        let delay = policy.backoff[min(attempt, policy.backoff.count - 1)]
        attempt += 1
        isPlaying = false
        notPlayingSince = ContinuousClock.now

        pendingReconnect = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self, self.isWanted else { return }
            self.pendingReconnect = nil
            self.onReconnect?(reason, self.attempt)
        }
    }
}
