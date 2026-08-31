import Foundation

/// Airtime — the only adapter that reports the current track as well as the show.
///
/// The API host drops the `.out` that the stream host carries: the stream is at
/// `<id>.out.airtime.pro`, the API at `<id>.airtime.pro`.
struct AirtimeAdapter: NowPlayingAdapter {
    func fetch(_ station: Station) async throws -> NowPlaying {
        let id = try HTTP.adapterId(station)
        let url = URL(string: "https://\(id).airtime.pro/api/live-info-v2")!
        let response = try await HTTP.get(url, as: Response.self)

        // `name` is "artist - title", which degrades to " - title" on a blank
        // artist, so the track is rebuilt from the metadata fields instead.
        let metadata = response.tracks?.current?.metadata
        let track = Cleanup.track(artist: metadata?.artistName, title: metadata?.trackTitle)
            ?? Cleanup.title(response.tracks?.current?.name)

        return NowPlaying(show: Cleanup.title(response.shows?.current?.name), track: track)
    }

    private struct Response: Decodable {
        @Lenient var shows: Shows?
        @Lenient var tracks: Tracks?

        struct Shows: Decodable {
            @Lenient var current: Show?
        }

        struct Show: Decodable {
            let name: String?
        }

        struct Tracks: Decodable {
            @Lenient var current: Track?
        }

        struct Track: Decodable {
            let name: String?
            @Lenient var metadata: Metadata?
        }

        struct Metadata: Decodable {
            let trackTitle: String?
            let artistName: String?
        }
    }
}
