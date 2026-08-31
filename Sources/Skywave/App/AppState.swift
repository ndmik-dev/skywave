import Foundation
import Observation
import SkywaveKit

/// Everything the panel renders, and the only thing that talks to the player.
@MainActor
@Observable
final class AppState {
    private(set) var catalog: Catalog?
    private(set) var current: Station?
    private(set) var nowPlaying = NowPlaying()
    private(set) var isPlaying = false
    private(set) var isLoading = false
    /// Set when the catalog itself will not load — the app has nothing to show.
    private(set) var fatalError: String?

    @ObservationIgnored private let player = StreamPlayer()
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var eventTask: Task<Void, Never>?

    /// Shows change on the hour and tracks every few minutes, so polling is lazy.
    private let pollInterval = Duration.seconds(15)

    init() {
        do {
            catalog = try Catalog.bundled()
        } catch {
            fatalError = "Could not load stations.json: \(error)"
        }
        eventTask = Task { [player] in
            for await event in player.events { self.handle(event) }
        }
    }

    var stations: [Station] { catalog?.stations ?? [] }

    func isCurrent(_ station: Station) -> Bool { current?.id == station.id }

    /// Click on a row: stop if it is already the current station, otherwise switch.
    func toggle(_ station: Station) {
        if isCurrent(station) {
            stop()
        } else {
            play(station)
        }
    }

    func play(_ station: Station) {
        current = station
        nowPlaying = NowPlaying()
        isLoading = true
        player.play(url: station.stream, gain: station.gain)
        startPolling(station)
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
        player.stop()
        current = nil
        nowPlaying = NowPlaying()
        isPlaying = false
        isLoading = false
    }

    // MARK: - Metadata

    private func startPolling(_ station: Station) {
        pollTask?.cancel()
        guard let adapter = Adapters.adapter(for: station) else {
            // icy and hls stations are pushed by the player instead.
            pollTask = nil
            return
        }
        pollTask = Task { [pollInterval] in
            while !Task.isCancelled {
                if let playing = try? await adapter.fetch(station), !Task.isCancelled {
                    self.apply(playing, from: station)
                }
                try? await Task.sleep(for: pollInterval)
            }
        }
    }

    /// Ignores answers that arrive after the user has already switched stations.
    private func apply(_ playing: NowPlaying, from station: Station) {
        guard isCurrent(station) else { return }
        nowPlaying = playing
    }

    private func handle(_ event: PlayerEvent) {
        switch event {
        case .timeControl(let state):
            isPlaying = state == .playing
            isLoading = state == .waitingToPlay
        case .metadata(let title):
            let parsed = IcyAdapter.parse(streamTitle: title)
            // Polled adapters own the show name; ICY only ever contributes a track.
            guard !parsed.isEmpty else { return }
            nowPlaying.track = parsed.track
        case .failedToPlayToEnd:
            isPlaying = false
            isLoading = false
        case .stalled, .errorLog, .itemStatus:
            break
        }
    }
}
