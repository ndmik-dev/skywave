import Foundation

/// Everything the player reports upward. The Phase 0 probe logs these; later
/// `AppState` reacts to them.
public enum PlayerEvent: Sendable {
    /// `AVPlayer.timeControlStatus` transition.
    case timeControl(TimeControl)
    /// `AVPlayerItem.status` transition.
    case itemStatus(ItemStatus)
    /// ICY `StreamTitle`, delivered by AVPlayer itself — no ICY parser needed.
    case metadata(String)
    /// `AVPlayerItemPlaybackStalled` — the failure this whole phase is looking for.
    case stalled
    case failedToPlayToEnd(String)
    /// New entry in the item's error log. Non-fatal on its own.
    case errorLog(String)

    public enum TimeControl: String, Sendable {
        case paused, waitingToPlay, playing

        init(_ raw: Int) {
            switch raw {
            case 1: self = .waitingToPlay
            case 2: self = .playing
            default: self = .paused
            }
        }
    }

    public enum ItemStatus: String, Sendable {
        case unknown, readyToPlay, failed
    }
}

extension PlayerEvent: CustomStringConvertible {
    public var description: String {
        switch self {
        case .timeControl(let s): "timeControl=\(s.rawValue)"
        case .itemStatus(let s): "itemStatus=\(s.rawValue)"
        case .metadata(let s): "metadata: \(s)"
        case .stalled: "STALLED"
        case .failedToPlayToEnd(let s): "FAILED: \(s)"
        case .errorLog(let s): "errorLog: \(s)"
        }
    }
}

/// Snapshot of `AVPlayerItem.accessLog()`, sampled on a timer by the probe.
public struct StreamStats: Sendable {
    public var stalls: Int
    public var bytesTransferred: Int64
    public var observedBitrate: Double
    public var indicatedBitrate: Double
    public var serverAddressChanges: Int
    public var isPlaybackLikelyToKeepUp: Bool
    public var isPlaybackBufferEmpty: Bool
}
