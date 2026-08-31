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
        // Headless playback check, used to verify App Transport Security rules
        // against the real bundle: --play <station-id> [seconds]
        if let flag = CommandLine.arguments.firstIndex(of: "--play"),
           flag + 1 < CommandLine.arguments.count {
            let id = CommandLine.arguments[flag + 1]
            let seconds = CommandLine.arguments.count > flag + 2
                ? Double(CommandLine.arguments[flag + 2]) ?? 20
                : 20
            exit(MainActor.assumeIsolated { Headless.play(stationId: id, seconds: seconds) })
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
