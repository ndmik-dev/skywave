import AVFoundation
import Foundation

/// Thin AVPlayer wrapper for a single live stream.
///
/// Deliberately does not retry, reconnect or hide anything: Phase 0 needs to see
/// AVPlayer's raw behaviour on an endless Icecast body with no `Content-Length`.
/// Resilience lands in a later session.
@MainActor
public final class StreamPlayer {
    public nonisolated let events: AsyncStream<PlayerEvent>
    private nonisolated let emit: AsyncStream<PlayerEvent>.Continuation

    private let player = AVPlayer()
    private var item: AVPlayerItem?
    private var metadataOutput: AVPlayerItemMetadataOutput?
    private var metadataDelegate: MetadataDelegate?
    private var observations: [NSKeyValueObservation] = []
    private var notificationTasks: [Task<Void, Never>] = []


    public init() {
        (events, emit) = AsyncStream.makeStream(bufferingPolicy: .unbounded)
    }

    /// - Parameters:
    ///   - gain: per-station level from the catalog, assigned straight to
    ///     `AVPlayer.volume`. It can only attenuate, so stations quieter than the
    ///     −16 LUFS target stay at 1.0.
    ///   - muted: silences output only. The stream is still fetched and decoded,
    ///     so an endurance run stays valid while muted.
    public func play(url: URL, gain: Float = 1.0, muted: Bool = false) {
        stop()

        let asset = AVURLAsset(url: url)
        let item = AVPlayerItem(asset: asset)
        self.item = item

        let output = AVPlayerItemMetadataOutput(identifiers: nil)
        let delegate = MetadataDelegate { [emit] title in emit.yield(.metadata(title)) }
        output.setDelegate(delegate, queue: .main)
        item.add(output)
        metadataOutput = output
        metadataDelegate = delegate

        observe(item: item)
        player.replaceCurrentItem(with: item)
        player.volume = gain
        player.isMuted = muted
        player.play()
    }

    public func stop() {
        notificationTasks.forEach { $0.cancel() }
        notificationTasks.removeAll()
        observations.removeAll()
        if let item, let metadataOutput { item.remove(metadataOutput) }
        metadataOutput = nil
        metadataDelegate = nil
        player.replaceCurrentItem(with: nil)
        item = nil
    }

    public func finish() {
        stop()
        emit.finish()
    }

    public var stats: StreamStats? {
        guard let item else { return nil }
        let event = item.accessLog()?.events.last
        return StreamStats(
            stalls: event?.numberOfStalls ?? 0,
            bytesTransferred: event?.numberOfBytesTransferred ?? 0,
            observedBitrate: event?.observedBitrate ?? 0,
            indicatedBitrate: event?.indicatedBitrate ?? 0,
            serverAddressChanges: event?.numberOfServerAddressChanges ?? 0,
            isPlaybackLikelyToKeepUp: item.isPlaybackLikelyToKeepUp,
            isPlaybackBufferEmpty: item.isPlaybackBufferEmpty
        )
    }

    // MARK: - Observation

    private func observe(item: AVPlayerItem) {
        observations.append(player.observe(\.timeControlStatus, options: [.new]) { [emit] player, _ in
            emit.yield(.timeControl(.init(player.timeControlStatus.rawValue)))
        })
        observations.append(item.observe(\.status, options: [.new]) { [emit] item, _ in
            let status: PlayerEvent.ItemStatus = switch item.status {
            case .readyToPlay: .readyToPlay
            case .failed: .failed
            default: .unknown
            }
            emit.yield(.itemStatus(status))
            if case .failed = status, let error = item.error {
                emit.yield(.failedToPlayToEnd(error.localizedDescription))
            }
        })

        watch(.AVPlayerItemPlaybackStalled, on: item) { [emit] _ in emit.yield(.stalled) }
        watch(.AVPlayerItemFailedToPlayToEndTime, on: item) { [emit] note in
            let error = note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
            emit.yield(.failedToPlayToEnd(error?.localizedDescription ?? "unknown"))
        }
        watch(.AVPlayerItemNewErrorLogEntry, on: item) { [emit] note in
            guard let item = note.object as? AVPlayerItem,
                  let entry = item.errorLog()?.events.last else { return }
            emit.yield(.errorLog("\(entry.errorStatusCode) \(entry.errorComment ?? "")"))
        }
    }

    private func watch(
        _ name: Notification.Name,
        on object: AVPlayerItem,
        handler: @escaping @Sendable (Notification) -> Void
    ) {
        let stream = NotificationCenter.default.notifications(named: name, object: object)
        notificationTasks.append(Task {
            for await note in stream { handler(note) }
        })
    }
}

/// AVPlayer surfaces ICY `StreamTitle` through the item's timed metadata.
///
/// Stations also emit `icy/json`, which on NTS is a literal empty `{}`, so items
/// are matched by identifier rather than taken as they come.
private final class MetadataDelegate: NSObject, AVPlayerItemMetadataOutputPushDelegate {
    private static let streamTitle = AVMetadataIdentifier("icy/StreamTitle")

    private let onTitle: @Sendable (String) -> Void

    init(onTitle: @escaping @Sendable (String) -> Void) {
        self.onTitle = onTitle
    }

    func metadataOutput(
        _ output: AVPlayerItemMetadataOutput,
        didOutputTimedMetadataGroups groups: [AVTimedMetadataGroup],
        from track: AVPlayerItemTrack?
    ) {
        for group in groups {
            for item in group.items {
                let isTitle = item.identifier == Self.streamTitle
                    || item.commonKey == .commonKeyTitle
                guard isTitle,
                      let value = item.value(forKey: "stringValue") as? String,
                      !value.isEmpty else { continue }
                onTitle(value)
            }
        }
    }
}
