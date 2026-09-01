import Foundation
import SkywaveKit

/// Headless check for the ring buffer: listens for a while, then writes a moment.
@MainActor
enum MomentCapture {
    static func run(stationId: String, seconds: Double) -> Int32 {
        guard let catalog = try? Catalog.bundled(),
              let station = catalog.station(id: stationId) else {
            print("no station '\(stationId)'")
            return 2
        }

        let player = StreamPlayer()
        player.play(url: station.stream, gain: station.gain, muted: true)
        print("\(station.name) — capturing for \(Int(seconds))s")
        fflush(stdout)
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))

        guard player.canCapture, let buffer = player.capture.buffer else {
            print("FAIL \(station.id): nothing to tap (HLS?)")
            player.finish()
            return 1
        }
        do {
            let moment = try Moments.save(buffer: buffer, station: station, title: nil)
            print(String(format: "OK %@ — %.1fs → %@",
                         station.id, moment.duration, moment.url.path))
            player.finish()
            return 0
        } catch {
            print("FAIL \(station.id): \(error)")
            player.finish()
            return 1
        }
    }
}
