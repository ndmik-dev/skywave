import AVFoundation
import Foundation
import SkywaveKit

/// Plays one station, muted, and reports what happened.
///
/// Runs inside the assembled `.app`, so unlike the standalone `Probe` it is
/// subject to the bundle's App Transport Security rules — which is the only way
/// to catch a station that plain HTTP or a redirect gets blocked on.
@MainActor
enum Headless {
    static func play(stationId: String, seconds: Double) -> Int32 {
        let catalog: Catalog
        do {
            catalog = try Catalog.bundled()
        } catch {
            print("catalog failed: \(error)")
            return 2
        }
        guard let station = catalog.station(id: stationId) else {
            print("no station '\(stationId)'; known: \(catalog.stations.map(\.id).joined(separator: ", "))")
            return 2
        }

        let player = StreamPlayer()
        var reachedPlaying = false
        var failure: String?

        let events = Task {
            for await event in player.events {
                switch event {
                case .timeControl(.playing): reachedPlaying = true
                case .failedToPlayToEnd(let message): failure = message
                case .itemStatus(.failed): failure = failure ?? "item failed"
                default: break
                }
                print("  \(event)")
            }
        }

        print("\(station.name) <\(station.stream.absoluteString)>")
        player.play(url: station.stream, gain: station.gain, muted: true)
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
        player.finish()
        events.cancel()

        if let failure {
            print("FAIL \(station.id): \(failure)")
            return 1
        }
        if !reachedPlaying {
            print("FAIL \(station.id): never started in \(Int(seconds))s")
            return 1
        }
        print("OK \(station.id)")
        return 0
    }
}
