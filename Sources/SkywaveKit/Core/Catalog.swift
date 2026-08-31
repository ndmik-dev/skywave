import Foundation

/// The station list is data, not code: stations die or go quiet often enough that
/// editing JSON has to be enough to keep up.
public struct Catalog: Codable, Sendable {
    public let version: Int
    public let measuredAt: String
    /// Target the per-station `gain` values normalise to.
    public let loudnessTargetLufs: Double
    public let stations: [Station]

    public var favorites: [Station] { stations.filter(\.favorite) }

    public func station(id: String) -> Station? {
        stations.first { $0.id == id }
    }

    /// Loads `stations.json` from the package bundle.
    public static func bundled() throws -> Catalog {
        guard let url = Bundle.module.url(forResource: "stations", withExtension: "json") else {
            throw CatalogError.missingResource
        }
        return try load(contentsOf: url)
    }

    public static func load(contentsOf url: URL) throws -> Catalog {
        try JSONDecoder().decode(Catalog.self, from: Data(contentsOf: url))
    }
}

public enum CatalogError: Error {
    case missingResource
}
