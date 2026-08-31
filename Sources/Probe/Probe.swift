import Foundation
import SkywaveKit

/// Phase 0 harness.
///
/// The one unverified assumption in the plan: does AVPlayer tolerate an endless
/// Icecast body with no `Content-Length`? This plays one stream for N minutes and
/// reports every stall, error-log entry and playback interruption.
///
/// Pass criterion: 30–40 min of continuous playback with no `AVPlayerItemPlaybackStalled`.
@main
struct Probe {
    static func main() async {
        let options = Options(CommandLine.arguments.dropFirst())
        let run = await Run(options: options).execute()
        exit(run ? 0 : 1)
    }
}

struct Station {
    let id: String
    let name: String
    let url: URL
    let gain: Float
}

/// Two hardcoded stations, per the plan: one plain Icecast, one behind NTS's relay.
let knownStations: [Station] = [
    Station(id: "nts", name: "NTS 1",
            url: URL(string: "https://stream-relay-geo.ntslive.net/stream")!,
            gain: 0.562),
    Station(id: "soma", name: "SomaFM Drone Zone",
            url: URL(string: "https://ice1.somafm.com/dronezone-256-mp3")!,
            gain: 0.955),
]

struct Options {
    var station = knownStations[0]
    var minutes = 40.0
    var heartbeat = 60.0
    /// Silences output; the stream is still fetched and decoded.
    var muted = false

    init(_ arguments: some Sequence<String>) {
        var iterator = arguments.makeIterator()
        while let flag = iterator.next() {
            if flag == "--mute" {
                muted = true
                continue
            }
            let value = iterator.next()
            switch flag {
            case "--station":
                guard let value else { break }
                if let known = knownStations.first(where: { $0.id == value }) {
                    station = known
                } else if let url = URL(string: value), url.scheme != nil {
                    station = Station(id: "custom", name: value, url: url, gain: 1.0)
                } else {
                    fail("unknown station '\(value)'; use \(knownStations.map(\.id).joined(separator: ", ")) or a URL")
                }
            case "--minutes":
                guard let number = value.flatMap({ Double($0) }) else { fail("--minutes needs a number") }
                minutes = number
            case "--heartbeat":
                guard let number = value.flatMap({ Double($0) }) else { fail("--heartbeat needs a number") }
                heartbeat = number
            default:
                fail("unknown flag '\(flag)'")
            }
        }
    }
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("skywave-probe: \(message)\n".utf8))
    exit(2)
}
