import Foundation

enum HTTP {
    /// Every one of these APIs is live data, so responses are never served from cache.
    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()

    /// Airtime, NTS and Radio.co use snake_case; Radiocult's camelCase keys pass
    /// through the conversion unchanged, so one decoder serves all four.
    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    static func get<T: Decodable>(_ url: URL, as type: T.Type) async throws -> T {
        let (data, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw AdapterError.badStatus(http.statusCode)
        }
        return try decoder.decode(T.self, from: data)
    }

    static func adapterId(_ station: Station) throws -> String {
        guard let id = station.adapterId, !id.isEmpty else {
            throw AdapterError.missingAdapterId(station: station.id)
        }
        return id
    }
}

/// Airtime returns `null` between shows and, on some versions, `[]` in place of an
/// object. Decoding leniently turns both into `nil` instead of a thrown error.
@propertyWrapper
struct Lenient<T: Decodable>: Decodable {
    var wrappedValue: T?

    init(wrappedValue: T?) {
        self.wrappedValue = wrappedValue
    }

    init(from decoder: any Decoder) throws {
        wrappedValue = try? T(from: decoder)
    }
}

extension KeyedDecodingContainer {
    func decode<T>(_ type: Lenient<T>.Type, forKey key: Key) throws -> Lenient<T> {
        (try? decodeIfPresent(type, forKey: key)) ?? Lenient(wrappedValue: nil)
    }
}
