import Foundation

/// Radio.co. Reports a single `current_track` title without separating show from
/// track, so it is surfaced as the show.
struct RadioCoAdapter: NowPlayingAdapter {
    func fetch(_ station: Station) async throws -> NowPlaying {
        let id = try HTTP.adapterId(station)
        let url = URL(string: "https://public.radio.co/stations/\(id)/status")!
        let response = try await HTTP.get(url, as: Response.self)

        guard response.status != "offline" else { return .offAir }
        return NowPlaying(show: Cleanup.title(response.currentTrack?.title))
    }

    private struct Response: Decodable {
        let status: String?
        @Lenient var currentTrack: Track?

        struct Track: Decodable {
            let title: String?
        }
    }
}
