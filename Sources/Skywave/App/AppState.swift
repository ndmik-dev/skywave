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

    /// Set when enabling "start at login" was refused.
    private(set) var loginItemError: String?

    @ObservationIgnored private let player = StreamPlayer()
    @ObservationIgnored private let nowPlayingCenter = NowPlayingCenter()
    @ObservationIgnored private let hotkeys = Hotkeys()
    @ObservationIgnored private var lastStation: Station?
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

        nowPlayingCenter.start()
        nowPlayingCenter.onPlay = { [weak self] in self?.resumeOrStart() }
        nowPlayingCenter.onPause = { [weak self] in self?.stop() }
        hotkeys.register { [weak self] in self?.togglePlayback() }
    }

    // MARK: - Login item

    var startsAtLogin: Bool { LoginItem.isEnabled }

    func setStartsAtLogin(_ enabled: Bool) {
        loginItemError = LoginItem.setEnabled(enabled)
    }

    var stations: [Station] { catalog?.stations ?? [] }

    func isCurrent(_ station: Station) -> Bool { current?.id == station.id }

    /// Media keys and the global hotkey: stop what is playing, or bring back the
    /// last station.
    func togglePlayback() {
        if current == nil {
            resumeOrStart()
        } else {
            stop()
        }
    }

    private func resumeOrStart() {
        guard current == nil else { return }
        // Falls back to the first favourite, so the hotkey does something useful
        // on a cold start.
        if let station = lastStation ?? catalog?.favorites.first {
            play(station)
        }
    }

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
        lastStation = station
        nowPlaying = NowPlaying()
        isLoading = true
        player.play(url: station.stream, gain: station.gain)
        startPolling(station)
        publish()
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
        player.stop()
        current = nil
        nowPlaying = NowPlaying()
        isPlaying = false
        isLoading = false
        publish()
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
        publish()
    }

    private func publish() {
        nowPlayingCenter.update(station: current, playing: nowPlaying, isPlaying: isPlaying)
    }

    private func handle(_ event: PlayerEvent) {
        switch event {
        case .timeControl(let state):
            isPlaying = state == .playing
            isLoading = state == .waitingToPlay
            publish()
        case .metadata(let title):
            // Airtime stations also push an ICY title, but it carries the show
            // name, which would overwrite the real track their API reports. So
            // ICY only speaks for stations that have no adapter to poll.
            guard let current, !current.adapter.isPolled else { return }
            let parsed = IcyAdapter.parse(streamTitle: title)
            guard !parsed.isEmpty else { return }
            nowPlaying.track = parsed.track
            publish()
        case .failedToPlayToEnd:
            isPlaying = false
            isLoading = false
            publish()
        case .stalled, .errorLog, .itemStatus:
            break
        }
    }
}
