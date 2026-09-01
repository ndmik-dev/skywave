import Foundation
import SkywaveKit

/// Favourites fall back to the catalog until the user has an opinion, and stay
/// theirs afterwards — a catalog update must never quietly rewrite a choice.
@MainActor
func favouriteChecks() {
    Expect.suite("favourites") {
        let catalog = try Catalog.bundled()
        let suite = "skywave.checks.favourites"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)

        var favourites = Favourites(defaults: defaults)
        for station in catalog.stations {
            Expect.that(favourites.contains(station) == station.favorite,
                        "\(station.id) starts as the catalog says")
        }

        let target = catalog.stations.first { !$0.favorite }!
        favourites.toggle(target, in: catalog)
        Expect.that(favourites.contains(target), "toggling adds \(target.id)")

        // The stored set has to survive being read back from scratch.
        let reloaded = Favourites(defaults: defaults)
        Expect.that(reloaded.contains(target), "\(target.id) survives a reload")
        Expect.equal(catalog.stations.filter(reloaded.contains).count,
                     catalog.favorites.count + 1, "the rest keep their state")

        var again = reloaded
        again.toggle(target, in: catalog)
        Expect.that(!again.contains(target), "toggling twice removes it again")

        defaults.removePersistentDomain(forName: suite)
    }
}


/// The countdown shipped an off-by-one that was only visible by watching it.
@MainActor
func countdownChecks() {
    Expect.suite("countdown") {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        let until = start.addingTimeInterval(900)
        // Full value the instant it is set.
        Expect.equal(Countdown.text(until: until, now: start), "15:00", "at once")
        // Never shows more time than is left.
        Expect.equal(Countdown.text(until: until, now: start.addingTimeInterval(0.4)),
                     "15:00", "part way into the first second")
        Expect.equal(Countdown.text(until: until, now: start.addingTimeInterval(1)),
                     "14:59", "after one second")
        Expect.equal(Countdown.text(until: until, now: start.addingTimeInterval(899.5)),
                     "0:01", "the last visible second")
        Expect.equal(Countdown.text(until: until, now: start.addingTimeInterval(900)),
                     "0:00", "exactly at the deadline")
        Expect.equal(Countdown.text(until: until, now: start.addingTimeInterval(950)),
                     "0:00", "never goes negative")
    }
}
