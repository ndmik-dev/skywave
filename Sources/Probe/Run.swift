import Foundation
import SkywaveKit

/// One probe run: start the stream, log events, sample stats, print a verdict.
@MainActor
final class Run {
    private let options: Options
    private let start = Date()
    private let player = StreamPlayer()

    private var stalls = 0
    private var failures: [String] = []
    private var errorLogEntries = 0
    private var titles: [String] = []
    private var reachedPlaying = false
    /// Wall-clock spent not playing after the first successful start.
    private var interrupted: TimeInterval = 0
    private var leftPlayingAt: Date?

    init(options: Options) {
        self.options = options
    }

    /// - Returns: `true` when the run meets the Phase 0 pass criterion.
    func execute() async -> Bool {
        let station = options.station
        log("station  \(station.name) <\(station.url.absoluteString)>")
        log("duration \(Int(options.minutes)) min · gain \(station.gain)\(options.muted ? " · muted" : "")")

        let events = Task { [player] in
            for await event in player.events { self.record(event) }
        }
        let heartbeat = Task { await self.heartbeatLoop() }

        player.play(url: station.url, gain: station.gain, muted: options.muted)
        try? await Task.sleep(for: .seconds(options.minutes * 60))

        heartbeat.cancel()
        player.finish()
        await events.value
        return report()
    }

    private func record(_ event: PlayerEvent) {
        switch event {
        case .stalled:
            stalls += 1
        case .failedToPlayToEnd(let message):
            failures.append(message)
        case .errorLog:
            errorLogEntries += 1
        case .metadata(let title):
            guard titles.last != title else { return }
            titles.append(title)
        case .timeControl(let state):
            switch state {
            case .playing:
                if let left = leftPlayingAt {
                    interrupted += Date().timeIntervalSince(left)
                    leftPlayingAt = nil
                }
                reachedPlaying = true
            default:
                if reachedPlaying, leftPlayingAt == nil { leftPlayingAt = Date() }
            }
        case .itemStatus:
            break
        }
        log(event.description)
    }

    private func heartbeatLoop() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(options.heartbeat))
            guard !Task.isCancelled, let stats = player.stats else { continue }
            log(String(
                format: "· %.1f MB · %.0f kbps observed · stalls(log) %d · keepUp %@ · bufferEmpty %@",
                Double(stats.bytesTransferred) / 1_048_576,
                stats.observedBitrate / 1000,
                stats.stalls,
                stats.isPlaybackLikelyToKeepUp ? "yes" : "no",
                stats.isPlaybackBufferEmpty ? "yes" : "no"
            ))
        }
    }

    private func report() -> Bool {
        if let left = leftPlayingAt { interrupted += Date().timeIntervalSince(left) }
        let elapsed = Date().timeIntervalSince(start)
        let passed = reachedPlaying && stalls == 0 && failures.isEmpty && interrupted < 1

        log("")
        log("── summary ──────────────────────────────")
        log(String(format: "elapsed      %.1f min", elapsed / 60))
        log(String(format: "interrupted  %.1f s", interrupted))
        log("stalls       \(stalls)")
        log("failures     \(failures.isEmpty ? "none" : failures.joined(separator: "; "))")
        log("error log    \(errorLogEntries) entries")
        log("titles       \(titles.count)")
        for title in titles.prefix(10) { log("  \(title)") }
        log(passed ? "VERDICT      PASS" : "VERDICT      FAIL")
        return passed
    }

    private func log(_ message: String) {
        let seconds = Int(Date().timeIntervalSince(start))
        print(String(format: "[%02d:%02d:%02d] %@",
                     seconds / 3600, (seconds / 60) % 60, seconds % 60, message))
        fflush(stdout)
    }
}
