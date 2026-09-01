import Foundation

/// How a station's now-playing information is obtained.
public enum AdapterKind: String, Codable, Sendable, CaseIterable {
    /// Metadata arrives through the player as ICY `StreamTitle`; no HTTP call.
    case icy
    case airtime
    case radiocult
    case radioco
    case nts
    /// Native HLS playback; metadata, if any, arrives through the player.
    case hls

    /// `false` for the kinds whose metadata is pushed by the player.
    public var isPolled: Bool {
        switch self {
        case .icy, .hls: false
        case .airtime, .radiocult, .radioco, .nts: true
        }
    }
}

public struct Station: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let name: String
    public let city: String
    public let stream: URL
    public let adapter: AdapterKind
    /// Station key within the adapter's API. Absent for `icy` and `hls`.
    public let adapterId: String?
    /// Assigned straight to `AVPlayer.volume`; see `Catalog.loudnessTargetLufs`.
    public let gain: Float
    public let measuredLufs: Double
    public let favorite: Bool
    /// Filename inside the bundle's `Logos` folder. Absent for stations whose
    /// site offers no usable mark — those fall back to a lettered tile.
    public let logo: String?
}
