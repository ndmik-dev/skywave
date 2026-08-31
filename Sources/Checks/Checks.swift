import Foundation
import SkywaveKit

/// Self-checks for the catalog and the adapters.
///
/// Pass `--live` to also poll every station that has an HTTP adapter. That part
/// depends on eight third-party services being up, so it is opt-in.
@main
struct Checks {
    static func main() async {
        let live = CommandLine.arguments.contains("--live")
        await MainActor.run {
            catalogChecks()
            cleanupChecks()
            icyChecks()
        }
        if live { await liveAdapterChecks() }
        exit(await MainActor.run { Expect.report() })
    }
}

@MainActor
func catalogChecks() {
    Expect.suite("catalog") {
        let catalog = try Catalog.bundled()
        Expect.equal(catalog.stations.count, 20, "station count")
        Expect.equal(catalog.favorites.count, 6, "favorite count")
        Expect.equal(catalog.loudnessTargetLufs, -16.0, "loudness target")

        let counts = catalog.stations.reduce(into: [AdapterKind: Int]()) {
            $0[$1.adapter, default: 0] += 1
        }
        Expect.equal(counts, [.icy: 11, .airtime: 3, .radiocult: 3, .nts: 1, .radioco: 1, .hls: 1],
                     "adapter distribution")

        for station in catalog.stations {
            // Polled adapters need a station key; pushed ones must not carry one.
            Expect.that(station.adapter.isPolled == (station.adapterId != nil),
                        "\(station.id) adapterId \(station.adapterId ?? "nil") for \(station.adapter.rawValue)")
            // AVPlayer.volume can only attenuate, so gain above 1.0 is meaningless.
            Expect.that(station.gain > 0 && station.gain <= 1.0, "\(station.id) gain \(station.gain)")
        }
        Expect.equal(Set(catalog.stations.map(\.id)).count, catalog.stations.count, "unique ids")
    }
}

@MainActor
func cleanupChecks() {
    Expect.suite("cleanup") {
        let entities = [
            ("I Don&#039;t Wanna", "I Don't Wanna"),
            ("BEACH NOIR W/ NICK LEÓN &amp; DJ Relax", "BEACH NOIR W/ NICK LEÓN & DJ Relax"),
            ("Lloyd &#039;Musclehead&#039; Saxon", "Lloyd 'Musclehead' Saxon"),
            ("&#x2014;dash", "—dash"),
            ("no entities here", "no entities here"),
            ("bare & ampersand", "bare & ampersand"),
        ]
        for (raw, expected) in entities {
            Expect.equal(Cleanup.decodeEntities(raw), expected, "decode \(raw)")
        }

        Expect.equal(Cleanup.title("Circles in Space by Radiocircolo 13.05.2026.mp3"),
                     "Circles in Space by Radiocircolo 13.05.2026", "drops audio extension")
        Expect.equal(Cleanup.title("Show 13.05.2026"), "Show 13.05.2026", "keeps non-audio suffix")
        Expect.equal(Cleanup.title(" - Circles in Space"), "Circles in Space", "leading separator")
        Expect.equal(Cleanup.title("Artist -"), "Artist", "trailing separator")
        Expect.equal(Cleanup.title(""), nil, "empty is nil")
        Expect.equal(Cleanup.title("   -  "), nil, "separator only is nil")

        Expect.equal(Cleanup.track(artist: "Qlank", title: "I Don&#039;t Wanna"),
                     "Qlank — I Don't Wanna", "joins artist and title")
        Expect.equal(Cleanup.track(artist: "", title: "owls"), "owls", "blank artist")
        Expect.equal(Cleanup.track(artist: "Qlank", title: nil), "Qlank", "missing title")
        Expect.equal(Cleanup.track(artist: nil, title: nil), nil, "both missing")
    }
}

@MainActor
func icyChecks() {
    Expect.suite("icy") {
        Expect.equal(IcyAdapter.parse(streamTitle: "Steve Roach - Structures from Silence").track,
                     "Steve Roach — Structures from Silence", "splits artist and title")
        // Many stations put a bare show name in StreamTitle, with no separator.
        Expect.equal(IcyAdapter.parse(streamTitle: "Rinse FM Breakfast").track,
                     "Rinse FM Breakfast", "passes through unsplittable titles")
        Expect.that(IcyAdapter.parse(streamTitle: "  ").isEmpty, "blank title yields nothing")
        // Kool FM, Rinse FM and SWU FM all ship this unfilled placeholder.
        Expect.that(IcyAdapter.parse(streamTitle: "Now Playing info goes here").isEmpty,
                    "filters the Rinse placeholder")
        Expect.that(IcyAdapter.parse(streamTitle: "Unknown").isEmpty, "filters Unknown")
    }
}

/// Polls every station with an HTTP adapter and prints what came back.
func liveAdapterChecks() async {
    let catalog: Catalog
    do {
        catalog = try Catalog.bundled()
    } catch {
        await MainActor.run { Expect.suite("live") { throw error } }
        return
    }

    let polled = catalog.stations.filter(\.adapter.isPolled)
    let results = await withTaskGroup(of: (Station, Result<NowPlaying, any Error>).self) { group in
        for station in polled {
            group.addTask {
                guard let adapter = Adapters.adapter(for: station) else {
                    return (station, .failure(AdapterError.notInResponse(station.id)))
                }
                do {
                    return (station, .success(try await adapter.fetch(station)))
                } catch {
                    return (station, .failure(error))
                }
            }
        }
        return await group.reduce(into: [(Station, Result<NowPlaying, any Error>)]()) { $0.append($1) }
    }

    await MainActor.run {
        Expect.suite("live adapters") {
            for (station, result) in results.sorted(by: { $0.0.id < $1.0.id }) {
                switch result {
                case .success(let playing):
                    // Off air is a legitimate answer, so it is not a failure.
                    Expect.that(playing.isOffAir || !playing.isEmpty,
                                "\(station.id): adapter returned nothing")
                    let detail = playing.isOffAir
                        ? "off air"
                        : [playing.show, playing.track].compactMap { $0 }.joined(separator: " · ")
                    print("  \(station.adapter.rawValue.padding(toLength: 10, withPad: " ", startingAt: 0)) \(station.id) — \(detail)")
                case .failure(let error):
                    Expect.that(false, "\(station.id): \(error)")
                }
            }
        }
    }
}
