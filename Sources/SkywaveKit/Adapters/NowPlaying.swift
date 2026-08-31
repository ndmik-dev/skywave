import Foundation

/// What is on air right now. Which fields are filled depends on the adapter:
/// only Airtime and Radio.co report a track alongside the show.
public struct NowPlaying: Sendable, Equatable {
    public var show: String?
    public var track: String?
    public var isOffAir: Bool

    public init(show: String? = nil, track: String? = nil, isOffAir: Bool = false) {
        self.show = show
        self.track = track
        self.isOffAir = isOffAir
    }

    public static let offAir = NowPlaying(isOffAir: true)

    public var isEmpty: Bool { show == nil && track == nil }
}

/// Polls one station's HTTP endpoint. Stations whose `adapter` is not `isPolled`
/// have no conforming type — their metadata is pushed by the player instead.
public protocol NowPlayingAdapter: Sendable {
    func fetch(_ station: Station) async throws -> NowPlaying
}

public enum AdapterError: Error, Sendable {
    /// The catalog entry lacks the `adapterId` its adapter needs.
    case missingAdapterId(station: String)
    case badStatus(Int)
    /// The endpoint answered, but not about this station.
    case notInResponse(String)
}

public enum Adapters {
    /// - Returns: `nil` for `icy` and `hls`, which are not polled.
    public static func adapter(for station: Station) -> (any NowPlayingAdapter)? {
        switch station.adapter {
        case .airtime: AirtimeAdapter()
        case .radiocult: RadiocultAdapter()
        case .radioco: RadioCoAdapter()
        case .nts: NTSAdapter()
        case .icy, .hls: nil
        }
    }
}
