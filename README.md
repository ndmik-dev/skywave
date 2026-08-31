# Skywave

macOS menubar player for 20 independent internet radio stations. See `CLAUDE.md`
for the plan and the decisions behind it.

Built with SwiftPM — there is no `.xcodeproj`, and Xcode is not required.

## Phase 0 probe

Endurance-tests AVPlayer against an endless Icecast stream, which is the one
architectural assumption the plan does not take on trust.

```
swift build -c release
.build/release/Probe --station soma --minutes 40 --mute
```

`--station` takes `nts`, `soma`, or any stream URL. `--mute` silences output
without changing what is fetched or decoded.
