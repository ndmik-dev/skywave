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
