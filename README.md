# Skywave

macOS menubar player for 20 independent internet radio stations. See `CLAUDE.md`
for the plan and the decisions behind it.

Built with SwiftPM — there is no `.xcodeproj`, and Xcode is not required. The
`.app` is assembled by a script, since Xcode is what normally does that.

## Build and run

```
./Scripts/bundle.sh --install
```

Builds, installs to `/Applications` and restarts the app. Drop `--install` to
build into `build/` only. The app is menubar-only (`LSUIElement`), so nothing
appears in the Dock. `⌥⌘P` plays and stops from anywhere.

Two headless modes run the real bundle, which is the only way to exercise its App
Transport Security rules — a station blocked by ATS plays fine from a plain
command-line build:

```
/Applications/Skywave.app/Contents/MacOS/Skywave --check
/Applications/Skywave.app/Contents/MacOS/Skywave --play dublab 20
```

## Checks

XCTest and swift-testing both ship with Xcode, so the checks are an executable
rather than a test target.

```
swift run Checks          # catalog and text handling
swift run Checks --live   # also polls all eight HTTP adapters
```

## Phase 0 probe

Endurance-tests AVPlayer against an endless Icecast stream, which is the one
architectural assumption the plan does not take on trust.

```
swift build -c release
.build/release/Probe --station soma --minutes 40 --mute
```

`--station` takes `nts`, `soma`, or any stream URL. `--mute` silences output
without changing what is fetched or decoded.
