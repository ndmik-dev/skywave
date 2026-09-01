import Foundation
import SkywaveKit

/// Round-trips a moment through the folder the panel reads.
///
/// The moments list once showed nothing but what the running session had kept,
/// because the listing was never called — a bug entirely invisible from the code
/// and obvious from the disk.
@MainActor
func momentChecks() async {
    guard let station = try? Catalog.bundled().station(id: "dublab") else {
        Expect.suite("moments") { Expect.that(false, "catalog missing dublab") }
        return
    }

    // Not real audio: this exercises naming, listing and deletion, not decoding.
    let payload = Data(repeating: 0x55, count: 4096)
    let title = "Check — Round / Trip"

    do {
        let before = await Moments.saved().count
        let moment = try await Moments.save(
            data: payload,
            fileExtension: "mp3",
            station: station,
            title: title
        )
        let listed = await Moments.saved()

        Expect.suite("moments") {
            Expect.that(listed.count == before + 1, "saved moment appears in the listing")
            guard let found = listed.first(where: { $0.id == moment.id }) else {
                Expect.that(false, "saved moment not found by id")
                return
            }
            Expect.equal(found.stationName, station.name, "station recovered from the filename")
            // The slash has to survive as something a path can hold.
            Expect.that(found.title?.hasPrefix("Check") == true,
                        "title recovered, got \(found.title ?? "nil")")
            Expect.that(!moment.url.lastPathComponent.contains("/"), "filename is path-safe")
        }

        try Moments.delete(moment)
        let after = await Moments.saved()
        Expect.suite("moments") {
            Expect.that(!after.contains { $0.id == moment.id }, "deleted moment leaves the listing")
        }
    } catch {
        Expect.suite("moments") { Expect.that(false, "round trip threw \(error)") }
    }
}
