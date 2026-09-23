import Foundation
import SkywaveKit

/// Prints the play log: `Skywave --played`.
///
/// The number the month is meant to produce, read from the command line so the
/// panel stays exactly as it was while the month runs.
@MainActor
enum Played {
    static func report() -> Int32 {
        guard let catalog = try? Catalog.bundled() else {
            print("catalog failed to load")
            return 2
        }
        let log = PlayLog()
        let reachability = Reachability()
        let window = 30

        let rows = catalog.stations
            .map { station in
                (station, log.daysPlayed(station, within: window), log.daysPlayedEver(station),
                 reachability.lastHeard(station))
            }
            .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.2 > $1.2 }

        print("played · last \(window) days · \(log.activeDays(within: window)) active days\n")
        let stamp = DateFormatter()
        stamp.dateFormat = "d MMM"
        for (station, recent, ever, last) in rows where ever > 0 {
            let lastText = last.map { stamp.string(from: $0) } ?? "—"
            print(String(format: "  %-18@ %2d d   ever %2d   last %@", station.name, recent, ever, lastText))
        }
        let never = rows.filter { $0.2 == 0 }
        if !never.isEmpty {
            print("\n  never: \(never.map(\.0.name).joined(separator: ", "))")
        }
        return 0
    }
}
