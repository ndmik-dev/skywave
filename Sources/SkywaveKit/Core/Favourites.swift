import Foundation

/// Which stations are favourites, once the user has had an opinion.
///
/// The catalog ships defaults, but it lives inside the app bundle and cannot be
/// written to. So changes are kept as a full replacement set in user defaults:
/// until one is stored the catalog decides, and afterwards the user does. That
/// way a catalog update never silently rewrites choices already made.
public struct Favourites {
    private static let key = "favouriteStationIDs"

    private var overrides: Set<String>?

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        overrides = (defaults.array(forKey: Self.key) as? [String]).map(Set.init)
    }

    private let defaults: UserDefaults

    public func contains(_ station: Station) -> Bool {
        overrides?.contains(station.id) ?? station.favorite
    }

    public mutating func toggle(_ station: Station, in catalog: Catalog?) {
        var set = overrides ?? Set((catalog?.favorites ?? []).map(\.id))
        if set.contains(station.id) {
            set.remove(station.id)
        } else {
            set.insert(station.id)
        }
        overrides = set
        defaults.set(Array(set), forKey: Self.key)
    }
}
