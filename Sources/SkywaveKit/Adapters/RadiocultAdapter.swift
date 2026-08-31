import Foundation

/// Radiocult. `content.title` is the show; `metadata.title` is the source
/// filename, so it is only a fallback.
struct RadiocultAdapter: NowPlayingAdapter {
    func fetch(_ station: Station) async throws -> NowPlaying {
        let id = try HTTP.adapterId(station)
        let url = URL(string: "https://api.radiocult.fm/api/station/\(id)/schedule/live")!
        let response = try await HTTP.get(url, as: Response.self)

        guard response.result.status != "offAir" else { return .offAir }
        let title = Cleanup.title(response.result.content?.title)
            ?? Cleanup.title(response.result.metadata?.title)
        return NowPlaying(show: title)
    }

    private struct Response: Decodable {
        let result: Result

        struct Result: Decodable {
            let status: String?
            @Lenient var content: Content?
            @Lenient var metadata: Metadata?
        }

        struct Content: Decodable {
            let title: String?
        }

        struct Metadata: Decodable {
            let title: String?
        }
    }
}
