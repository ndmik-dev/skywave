import Foundation
import SkywaveKit

/// Headless check for the recorder: holds a stretch of a station, then saves it.
@MainActor
enum MomentCapture {
    static func run(stationId: String, seconds: Double) -> Int32 {
        guard let catalog = try? Catalog.bundled(),
              let station = catalog.station(id: stationId) else {
            print("no station '\(stationId)'")
            return 2
        }

        let recorder = StreamRecorder()
        recorder.start(url: station.stream)
        print("\(station.name) — holding \(Int(seconds))s")
        fflush(stdout)
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))

        guard let held = recorder.snapshot() else {
            print("FAIL \(station.id): nothing captured")
            recorder.stop()
            return 1
        }
        recorder.stop()

        var code: Int32?
        Task {
            do {
                let moment = try await Moments.save(
                    data: held.data,
                    fileExtension: held.fileExtension,
                    station: station,
                    title: nil
                )
                print(String(format: "OK %@ — %.1fs · %.2f MB · %@",
                             station.id, moment.duration,
                             Double(held.data.count) / 1_048_576,
                             moment.url.lastPathComponent))
                code = 0
            } catch {
                print("FAIL \(station.id): \(error)")
                code = 1
            }
        }

        // The write and the duration probe are async; pump the runloop until
        // they land, or give up after ten seconds.
        let deadline = Date().addingTimeInterval(10)
        while code == nil, Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        return code ?? 1
    }
}
