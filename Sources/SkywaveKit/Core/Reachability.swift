import Foundation

/// When each station was last heard playing.
///
/// Stations in this catalog die quietly — three of twenty-four went dark over
/// eighteen months. Without a record, a station that has been dead for a year is
/// indistinguishable from one having a slow morning, and the list rots silently.
public struct Reachability {
    private static let key = "stationLastHeard"

    private let defaults: UserDefaults
    private var heard: [String: Date]

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.dictionary(forKey: Self.key) as? [String: Double] ?? [:]
        heard = stored.mapValues(Date.init(timeIntervalSinceReferenceDate:))
    }

    public func lastHeard(_ station: Station) -> Date? {
        heard[station.id]
    }

    public mutating func noteHeard(_ station: Station, at date: Date = Date()) {
        heard[station.id] = date
        defaults.set(heard.mapValues(\.timeIntervalSinceReferenceDate), forKey: Self.key)
    }

    /// How long a station has been silent, for the panel to put into words.
    public func silence(_ station: Station, now: Date = Date()) -> TimeInterval? {
        lastHeard(station).map { now.timeIntervalSince($0) }
    }
}
