import Foundation

/// NTS. One endpoint covers both channels, keyed by `channel_name`, which is what
/// a station's `adapterId` holds ("1" or "2"). Tracklists are Supporter-only and
/// out of scope.
struct NTSAdapter: NowPlayingAdapter {
    func fetch(_ station: Station) async throws -> NowPlaying {
        let id = try HTTP.adapterId(station)
        let url = URL(string: "https://www.nts.live/api/v2/live")!
        let response = try await HTTP.get(url, as: Response.self)

        guard let channel = response.results.first(where: { $0.channelName == id }) else {
            throw AdapterError.notInResponse(id)
        }
        return NowPlaying(show: Cleanup.title(channel.now?.broadcastTitle))
    }

    private struct Response: Decodable {
        let results: [Channel]

        struct Channel: Decodable {
            let channelName: String?
            @Lenient var now: Broadcast?
        }

        struct Broadcast: Decodable {
            let broadcastTitle: String?
        }
    }
}
