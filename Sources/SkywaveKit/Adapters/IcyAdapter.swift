import Foundation

/// ICY stations have no endpoint to poll: AVPlayer surfaces `StreamTitle` itself
/// through the item's timed metadata. This only shapes that string.
///
/// Measured across the catalog's 11 ICY stations: 8 deliver a real title, the two
/// SomaFM streams and Operator Radio deliver nothing through AVPlayer at all, and
/// the three Rinse-hosted stations ship an unfilled placeholder.
public enum IcyAdapter {
    /// Titles that carry no information, matched case-insensitively after cleanup.
    private static let placeholders: Set<String> = [
        "now playing info goes here",
        "unknown",
        "unknown artist",
        "unknown - unknown",
        "{}",
    ]

    /// Splits the conventional "Artist - Title" form; anything else is passed
    /// through whole rather than guessed at.
    public static func parse(streamTitle raw: String) -> NowPlaying {
        guard let title = Cleanup.title(raw),
              !placeholders.contains(title.lowercased()) else { return NowPlaying() }
        guard let separator = title.range(of: " - ") else {
            return NowPlaying(track: title)
        }
        let artist = String(title[..<separator.lowerBound])
        let name = String(title[separator.upperBound...])
        return NowPlaying(track: Cleanup.track(artist: artist, title: name) ?? title)
    }
}
