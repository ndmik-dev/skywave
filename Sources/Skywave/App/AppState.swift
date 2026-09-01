import AppKit
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
    /// Why the stream is being re-established, if it is.
    private(set) var reconnecting: ReconnectReason?
    private(set) var moments: [Moment] = []
    /// Briefly set after a moment is kept, so the panel can say so.
    private(set) var justSaved: Moment?
    private(set) var momentError: String?

    /// What is on air across the catalog, keyed by station id. Only the eight
    /// polled stations can appear here — the rest reveal nothing until played.
    private(set) var onAir: [String: NowPlaying] = [:]

    @ObservationIgnored private let player = StreamPlayer()
    @ObservationIgnored private let nowPlayingCenter = NowPlayingCenter()
    @ObservationIgnored private let hotkeys = Hotkeys()
    @ObservationIgnored private let resilience = Resilience()
    @ObservationIgnored private let recorder = StreamRecorder()
    @ObservationIgnored private let notifications = Notifications()
    @ObservationIgnored private var lastStation: Station?
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var boardTask: Task<Void, Never>?
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
        hotkeys.register(
            playPause: { [weak self] in self?.togglePlayback() },
            keepMoment: { [weak self] in self?.saveMoment() }
        )

        resilience.onReconnect = { [weak self] reason, attempt in
            self?.reconnect(reason, attempt: attempt)
        }
        resilience.start()
        notifications.requestAuthorization()
    }

    // MARK: - On air across the catalog

    /// Refreshes the whole board while the panel is open, and stops when it closes.
    func startWatchingOnAir() {
        guard boardTask == nil else { return }
        boardTask = Task {
            while !Task.isCancelled {
                await refreshOnAir()
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    func stopWatchingOnAir() {
        boardTask?.cancel()
        boardTask = nil
    }

    private func refreshOnAir() async {
        let polled = stations.filter(\.adapter.isPolled)
        let fetched = await withTaskGroup(of: (String, NowPlaying)?.self) { group in
            for station in polled {
                guard let adapter = Adapters.adapter(for: station) else { continue }
                group.addTask {
                    guard let playing = try? await adapter.fetch(station) else { return nil }
                    return (station.id, playing)
                }
            }
            var result: [String: NowPlaying] = [:]
            for await entry in group {
                if let entry { result[entry.0] = entry.1 }
            }
            return result
        }
        guard !Task.isCancelled else { return }
        // Merged, not replaced, so a station that failed this round keeps its
        // last known line instead of blinking out.
        onAir.merge(fetched) { _, new in new }
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
        notifications.reset(station: station)
        nowPlaying = NowPlaying()
        reconnecting = nil
        isLoading = true
        resilience.noteStarted()
        player.play(url: station.stream, gain: station.gain)
        // A second connection, because the player's own audio is unreachable on
        // most stations. HLS is served in segments, so there is nothing to keep.
        if station.adapter != .hls {
            recorder.start(url: station.stream)
        }
        startPolling(station)
        publish()
    }

    // MARK: - Moments

    /// True while there is something worth keeping.
    var canSaveMoment: Bool { recorder.isRunning }

    func saveMoment() {
        guard let station = current, let held = recorder.snapshot() else {
            momentError = "Nothing captured yet"
            return
        }
        Task {
            do {
                let moment = try await Moments.save(
                    data: held.data,
                    fileExtension: held.fileExtension,
                    station: station,
                    title: nowPlaying.track ?? nowPlaying.show
                )
                justSaved = moment
                momentError = nil
                await refreshMoments()
            } catch {
                momentError = error.localizedDescription
            }
        }
    }

    func refreshMoments() async {
        moments = await Moments.saved()
    }

    func delete(_ moment: Moment) {
        try? Moments.delete(moment)
        moments.removeAll { $0.id == moment.id }
    }

    func reveal(_ moment: Moment) {
        NSWorkspace.shared.activateFileViewerSelecting([moment.url])
    }

    /// Re-establishes the current stream, keeping the station selected so the
    /// panel does not flicker back to "nothing on air".
    /// - Parameter attempt: consecutive failures since playback last worked.
    ///   Past a few, the silence needs explaining.
    private func reconnect(_ reason: ReconnectReason, attempt: Int) {
        guard let station = current else { return }
        if attempt >= 3 { notifications.unreachable(station: station) }
        reconnecting = reason
        isLoading = true
        resilience.noteStarted()
        player.play(url: station.stream, gain: station.gain)
        if station.adapter != .hls {
            recorder.start(url: station.stream)
        }
        publish()
    }

    func stop() {
        resilience.noteStopped()
        recorder.stop()
        pollTask?.cancel()
        pollTask = nil
        player.stop()
        current = nil
        nowPlaying = NowPlaying()
        isPlaying = false
        isLoading = false
        reconnecting = nil
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
        onAir[station.id] = playing
        if let show = playing.show {
            notifications.showChanged(station: station, to: show)
        }
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
            if state == .playing {
                resilience.notePlaying()
                reconnecting = nil
                if let current { notifications.recovered(station: current) }
            } else {
                resilience.notePaused()
            }
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
            resilience.noteFailed()
            publish()
        case .stalled:
            resilience.noteStalled()
        case .errorLog, .itemStatus:
            break
        }
    }
}
