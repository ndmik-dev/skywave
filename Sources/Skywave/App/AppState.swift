import AVFoundation
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
    /// Paused keeps the station selected; live radio has nothing to resume into,
    /// so resuming re-establishes the stream at whatever is on now.
    private(set) var isPaused = false
    /// Set when the catalog itself will not load — the app has nothing to show.
    private(set) var loadError: String?

    /// Set when enabling "start at login" was refused.
    private(set) var loginItemError: String?
    /// Why the stream is being re-established, if it is.
    private(set) var reconnecting: ReconnectReason?
    private(set) var moments: [Moment] = []
    /// Set briefly after a moment is kept, so the panel can confirm it. Saving
    /// is otherwise completely silent, which from a global hotkey is unnerving.
    private(set) var justSaved: Moment?
    private(set) var momentError: String?
    /// Observable, unlike the recorder itself: the panel has to redraw when a
    /// station starts, or the button stays frozen in its old state.
    private(set) var canSaveMoment = false

    /// Stations that were given up on this session. Cleared the moment one is
    /// heard again, so a station coming back needs no restart.
    private(set) var unreachable: Set<String> = []
    /// Bumped when the last-heard record changes, so rows redraw.
    private(set) var reachabilityRevision = 0

    /// When playback will stop by itself, if a sleep timer is running.
    private(set) var sleepUntil: Date?
    /// The moment being previewed, if any.
    private(set) var playingMomentID: String?

    /// What is on air across the catalog, keyed by station id. Only the eight
    /// polled stations can appear here — the rest reveal nothing until played.
    private(set) var onAir: [String: NowPlaying] = [:]

    @ObservationIgnored private let player = StreamPlayer()
    @ObservationIgnored private let nowPlayingCenter = NowPlayingCenter()
    @ObservationIgnored private let hotkeys = Hotkeys()
    @ObservationIgnored private let resilience = Resilience()
    @ObservationIgnored private let recorder = StreamRecorder()
    @ObservationIgnored private let notifications = Notifications()
    /// Bumped whenever favourites change, so the list redraws — `Favourites`
    /// itself lives in user defaults, which observation cannot see.
    private(set) var favouritesRevision = 0
    @ObservationIgnored private var favourites = Favourites()
    @ObservationIgnored private var reachability = Reachability()
    @ObservationIgnored private var lastStation: Station?
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var boardTask: Task<Void, Never>?
    @ObservationIgnored private var eventTask: Task<Void, Never>?
    @ObservationIgnored private var sleepTask: Task<Void, Never>?
    @ObservationIgnored private var sleepSetAt = Date.distantPast
    @ObservationIgnored private var momentPlayer: AVAudioPlayer?

    /// Shows change on the hour and tracks every few minutes, so polling is lazy.
    private let pollInterval = Duration.seconds(15)

    init() {
        do {
            catalog = try Catalog.bundled()
        } catch {
            loadError = "Could not load stations.json: \(error)"
        }
        eventTask = Task { [player] in
            for await event in player.events { self.handle(event) }
        }

        nowPlayingCenter.start()
        nowPlayingCenter.onPlay = { [weak self] in self?.resumeOrStart() }
        nowPlayingCenter.onPause = { [weak self] in self?.pause() }
        hotkeys.register(
            playPause: { [weak self] in self?.togglePlayback() },
            keepMoment: { [weak self] in self?.saveMoment() }
        )

        resilience.onReconnect = { [weak self] reason, attempt in
            self?.reconnect(reason, attempt: attempt)
        }
        resilience.onGaveUp = { [weak self] in self?.giveUp() }
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

    func isUnreachable(_ station: Station) -> Bool {
        unreachable.contains(station.id)
    }

    /// When the station was last actually heard, for the panel to say so.
    func lastHeard(_ station: Station) -> Date? {
        _ = reachabilityRevision
        return reachability.lastHeard(station)
    }

    /// Retrying was abandoned. The station stays selected and stays named — it
    /// is the list's record of what has gone quiet.
    private func giveUp() {
        guard let station = current else { return }
        unreachable.insert(station.id)
        reconnecting = nil
        isLoading = false
        isPlaying = false
        recorder.stop()
        canSaveMoment = false
        publish()
    }

    func isFavourite(_ station: Station) -> Bool {
        _ = favouritesRevision
        return favourites.contains(station)
    }

    func toggleFavourite(_ station: Station) {
        favourites.toggle(station, in: catalog)
        favouritesRevision += 1
    }

    func isCurrent(_ station: Station) -> Bool { current?.id == station.id }

    /// Media keys and the global hotkey.
    func togglePlayback() {
        if let current, !isPaused {
            pause()
        } else if let station = current ?? lastStation ?? catalog?.favorites.first {
            // Falls back to the first favourite, so the hotkey does something
            // useful on a cold start.
            play(station)
        }
    }

    private func resumeOrStart() {
        guard !isPlaying else { return }
        if let station = current ?? lastStation ?? catalog?.favorites.first {
            play(station)
        }
    }

    /// Drops the connection but keeps the station, so the panel still shows what
    /// it is tuned to and one press picks it back up.
    func pause() {
        // Any running fade belongs to a timer that is now moot.
        if sleepUntil != nil { setSleepTimer(minutes: nil) }
        resilience.noteStopped()
        recorder.stop()
        canSaveMoment = false
        pollTask?.cancel()
        pollTask = nil
        player.stop()
        isPlaying = false
        isLoading = false
        isPaused = true
        reconnecting = nil
        publish()
    }

    /// Click on a row: pause if it is already the current station, otherwise switch.
    func toggle(_ station: Station) {
        if isCurrent(station), !isPaused {
            pause()
        } else {
            play(station)
        }
    }

    func play(_ station: Station) {
        stopMoment()
        unreachable.remove(station.id)
        current = station
        lastStation = station
        notifications.reset(station: station)
        nowPlaying = NowPlaying()
        reconnecting = nil
        isPaused = false
        isLoading = true
        momentError = nil
        justSaved = nil
        resilience.noteStarted()
        player.play(url: station.stream, gain: station.gain)
        startCapture(for: station)
        startPolling(station)
        publish()
    }

    /// A second connection, because the player's own audio is unreachable on
    /// most stations. HLS is served in segments, so there is nothing to keep.
    private func startCapture(for station: Station) {
        guard station.adapter != .hls else {
            canSaveMoment = false
            return
        }
        recorder.start(url: station.stream)
        canSaveMoment = true
    }

    // MARK: - Sleep timer

    /// The offered lengths, in minutes. Clicking the footer row walks the list
    /// and then switches off, which keeps the whole feature to one row.
    static let sleepOptions = [15, 30, 60, 90]
    /// Long enough to be a fade rather than a cut, short enough not to eat a
    /// noticeable slice of the timer.
    private static let sleepFade = Duration.seconds(10)

    /// Minutes on the current timer, or nil when none is set.
    var sleepMinutes: Int? {
        guard let sleepUntil else { return nil }
        return Self.sleepOptions.first { minutes in
            // Match on what was set, not on what is left.
            abs(sleepUntil.timeIntervalSince(sleepSetAt) - Double(minutes * 60)) < 1
        }
    }

    func cycleSleepTimer() {
        let next: Int?
        switch sleepMinutes {
        case nil: next = Self.sleepOptions.first
        case let current?:
            let index = Self.sleepOptions.firstIndex(of: current).map { $0 + 1 } ?? Self.sleepOptions.count
            next = index < Self.sleepOptions.count ? Self.sleepOptions[index] : nil
        }
        setSleepTimer(minutes: next)
    }

    func setSleepTimer(minutes: Int?) {
        sleepTask?.cancel()
        sleepTask = nil
        guard let minutes else {
            sleepUntil = nil
            // A fade may have already started; put the level back.
            if let current { player.setVolume(current.gain) }
            return
        }
        sleepSetAt = Date()
        let deadline = sleepSetAt.addingTimeInterval(Double(minutes * 60))
        sleepUntil = deadline
        sleepTask = Task { [weak self] in
            let total = Duration.seconds(Double(minutes * 60))
            try? await Task.sleep(for: total - Self.sleepFade)
            guard !Task.isCancelled, let self else { return }
            await self.player.fadeOut(over: Self.sleepFade)
            guard !Task.isCancelled else { return }
            self.sleepUntil = nil
            self.pause()
            // pause() released the item; the next play() sets the gain again.
        }
    }

    // MARK: - Moments

    func saveMoment() {
        guard let station = current else {
            momentError = "Nothing is playing"
            return
        }
        guard let held = recorder.snapshot() else {
            momentError = station.adapter == .hls
                ? "\(station.name) cannot be captured"
                : "Nothing captured yet"
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
                // Long enough to notice, short enough not to become furniture.
                try? await Task.sleep(for: .seconds(4))
                if justSaved?.id == moment.id { justSaved = nil }
            } catch {
                momentError = error.localizedDescription
            }
        }
    }

    func refreshMoments() async {
        moments = await Moments.saved()
    }

    func delete(_ moment: Moment) {
        if playingMomentID == moment.id { stopMoment() }
        try? Moments.delete(moment)
        moments.removeAll { $0.id == moment.id }
    }

    func reveal(_ moment: Moment) {
        NSWorkspace.shared.activateFileViewerSelecting([moment.url])
    }

    /// Previews a kept moment in place. Radio pauses first — two things playing
    /// over each other is never what was meant.
    func toggleMoment(_ moment: Moment) {
        if playingMomentID == moment.id {
            stopMoment()
            return
        }
        stopMoment()
        if isPlaying { pause() }
        guard let player = try? AVAudioPlayer(contentsOf: moment.url) else {
            momentError = "Could not play \(moment.url.lastPathComponent)"
            return
        }
        momentPlayer = player
        playingMomentID = moment.id
        player.play()
        // AVAudioPlayer's delegate is one more object to own for a preview this
        // small; polling the end is enough.
        Task { [weak self] in
            while let self, self.momentPlayer === player, player.isPlaying {
                try? await Task.sleep(for: .milliseconds(300))
            }
            if let self, self.momentPlayer === player { self.stopMoment() }
        }
    }

    func stopMoment() {
        momentPlayer?.stop()
        momentPlayer = nil
        playingMomentID = nil
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
        startCapture(for: station)
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
                if let current {
                    notifications.recovered(station: current)
                    unreachable.remove(current.id)
                    reachability.noteHeard(current)
                    reachabilityRevision += 1
                }
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
