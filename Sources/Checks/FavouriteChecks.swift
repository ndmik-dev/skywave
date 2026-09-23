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


/// Reachability is what makes a rotting catalog visible, so its wording and its
/// persistence are both worth pinning down.
@MainActor
func reachabilityChecks() {
    Expect.suite("reachability") {
        let now = Date(timeIntervalSinceReferenceDate: 1_000_000)
        Expect.equal(Silence.text(since: nil, now: now), "never heard", "never played")
        Expect.equal(Silence.text(since: now.addingTimeInterval(-60), now: now),
                     "heard just now", "minutes ago")
        Expect.equal(Silence.text(since: now.addingTimeInterval(-7200), now: now),
                     "heard 2h ago", "hours ago")
        Expect.equal(Silence.text(since: now.addingTimeInterval(-86_400 * 3), now: now),
                     "heard 3d ago", "days ago")
        // Past a fortnight the exact count stops meaning anything.
        Expect.that(Silence.text(since: now.addingTimeInterval(-86_400 * 400), now: now)
                        .hasPrefix("last heard"), "a year ago names the month")

        let suite = "skywave.checks.reachability"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let station = try Catalog.bundled().stations[0]

        var reachability = Reachability(defaults: defaults)
        Expect.that(reachability.lastHeard(station) == nil, "unknown before anything is heard")
        reachability.noteHeard(station, at: now)
        Expect.that(Reachability(defaults: defaults).lastHeard(station) != nil,
                    "last heard survives a reload")
        defaults.removePersistentDomain(forName: suite)
    }
}


/// The play log is the one number the month is meant to produce, so its
/// window arithmetic has to be right on the edges.
@MainActor
func playLogChecks() {
    Expect.suite("play log") {
        let suite = "skywave.checks.playlog"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let catalog = try Catalog.bundled()
        let nts = catalog.stations[0], dublab = catalog.stations[1]
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date()).addingTimeInterval(12 * 3600)
        func daysAgo(_ n: Int) -> Date { calendar.date(byAdding: .day, value: -n, to: today)! }

        var log = PlayLog(defaults: defaults)
        Expect.equal(log.daysPlayed(nts, now: today), 0, "nothing before anything is heard")

        log.notePlayed(nts, on: today)
        log.notePlayed(nts, on: today.addingTimeInterval(3600))
        Expect.equal(log.daysPlayed(nts, now: today), 1, "two plays on one day count once")

        log.notePlayed(nts, on: daysAgo(29))
        Expect.equal(log.daysPlayed(nts, now: today), 2, "day 29 back is inside a 30-day window")
        log.notePlayed(nts, on: daysAgo(30))
        Expect.equal(log.daysPlayed(nts, now: today), 2, "day 30 back is outside it")
        Expect.equal(log.daysPlayedEver(nts), 3, "but still counted ever")

        log.notePlayed(dublab, on: daysAgo(29))
        Expect.equal(log.activeDays(now: today), 2, "active days are distinct across stations")

        Expect.equal(PlayLog(defaults: defaults).daysPlayedEver(nts), 3, "survives a reload")
        defaults.removePersistentDomain(forName: suite)
    }
}
