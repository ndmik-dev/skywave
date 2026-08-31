import SwiftUI
import SkywaveKit

@main
enum Main {
    static func main() {
        // Smoke test for the assembled .app: proves Bundle.module resolves once
        // the resource bundle sits in Contents/Resources.
        if CommandLine.arguments.contains("--check") {
            do {
                let catalog = try Catalog.bundled()
                print("catalog ok — \(catalog.stations.count) stations, \(catalog.favorites.count) favorites")
                exit(0)
            } catch {
                print("catalog failed: \(error)")
                exit(1)
            }
        }
        SkywaveApp.main()
    }
}

struct SkywaveApp: App {
    @State private var state = AppState()

    var body: some Scene {
        MenuBarExtra {
            PanelView(state: state)
        } label: {
            // Filled while something is on air, so the menubar reads at a glance.
            Image(systemName: state.isPlaying
                  ? "dot.radiowaves.left.and.right"
                  : "antenna.radiowaves.left.and.right")
        }
        // .window, not .menu: the panel is a custom view, not a list of items.
        .menuBarExtraStyle(.window)
    }
}
