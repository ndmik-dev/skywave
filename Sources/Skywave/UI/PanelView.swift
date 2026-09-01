import SwiftUI
import SkywaveKit

enum PanelMode: String, CaseIterable, Identifiable {
    case stations = "Stations"
    case moments = "Moments"

    var id: String { rawValue }
}

struct PanelView: View {
    @Bindable var state: AppState
    @State private var mode: PanelMode = .stations
    /// The moments list has nothing focusable in it, so without somewhere for
    /// focus to live the panel received no key events at all there — which is
    /// why ⌘2 worked and ⌘1 did not.
    @FocusState private var panelFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let message = state.loadError {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding()
            } else {
                if let reason = state.reconnecting {
                    StateNote(reason: reason)
                }
                OnAir(state: state, mode: $mode)
                Divider()
                switch mode {
                case .stations: StationList(state: state)
                case .moments:
                    // Moments saved in earlier sessions live on disk; without
                    // this the list only ever showed what this run had kept.
                    MomentsList(state: state)
                        .task { await state.refreshMoments() }
                }
                Divider()
                Footer(state: state, mode: mode)
            }
        }
        .frame(width: Theme.width)
        .focusable()
        .focusEffectDisabled()
        .focused($panelFocused)
        .onChange(of: mode) { _, new in
            // In stations mode the search field wants focus; take it only when
            // nothing else will.
            if new == .moments { panelFocused = true }
        }
        .onKeyPress(phases: .down) { press in
            guard press.modifiers.contains(.command) else { return .ignored }
            switch press.characters {
            case "1": mode = .stations; return .handled
            case "2": mode = .moments; return .handled
            default: return .ignored
            }
        }
        .onAppear { state.startWatchingOnAir() }
        .onDisappear { state.stopWatchingOnAir() }
    }
}

/// The header, and the anchor of the panel: it stays put in every mode.
private struct OnAir: View {
    @Bindable var state: AppState
    @Binding var mode: PanelMode

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 11) {
                if let station = state.current {
                    Artwork(station: station)
                } else {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(.quaternary)
                        .frame(width: 46, height: 46)
                        .overlay(
                            Image(systemName: "antenna.radiowaves.left.and.right")
                                .foregroundStyle(.secondary)
                        )
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(state.current?.name ?? "Nothing on air")
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                    Text(showLine)
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if !trackLine.isEmpty {
                        HStack(spacing: 5) {
                            if state.isPlaying {
                                PulsingDot()
                            }
                            Text(trackLine)
                                .font(.system(size: 11.5))
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                    }
                }
                Spacer(minLength: 0)

                if state.current != nil {
                    Button(action: state.togglePlayback) {
                        Image(systemName: state.isPaused ? "play.fill" : "pause.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.white)
                            .frame(width: 34, height: 34)
                            .background(Theme.signal, in: .circle)
                    }
                    .buttonStyle(.plain)
                    .help(state.isPaused ? "Resume" : "Pause")
                    .accessibilityLabel(state.isPaused ? "Resume" : "Pause")
                }
            }

            ModeSwitch(mode: $mode)
                .padding(.top, 12)
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }

    /// Second line: the show if the station reports one, otherwise where it is.
    private var showLine: String {
        guard let station = state.current else { return "Pick a station" }
        if state.isUnreachable(station) { return "not responding" }
        if state.isPaused { return "paused" }
        if state.isLoading { return "connecting…" }
        if state.nowPlaying.isOffAir { return "off air" }
        return state.nowPlaying.show ?? station.city
    }

    /// Third line: the track if there is one. Never repeats the city, which the
    /// line above already carries when there is no show.
    private var trackLine: String {
        guard let station = state.current else { return "⌥⌘P" }
        // A dead station is the one case where the useful thing to show is when
        // it was last alive, so a rotting catalog is visible rather than guessed.
        if state.isUnreachable(station) {
            return Silence.text(since: state.lastHeard(station))
        }
        if let track = state.nowPlaying.track { return track }
        guard state.isPlaying else { return "" }
        return state.nowPlaying.show == nil ? "on air" : "on air · \(station.city)"
    }
}

/// The live indicator: a slow pulse, since a static dot reads as decoration.
private struct PulsingDot: View {
    @State private var dim = false

    var body: some View {
        Circle()
            .fill(Theme.onAir)
            .frame(width: 6, height: 6)
            .opacity(dim ? 0.3 : 1)
            .animation(.easeInOut(duration: 1.3).repeatForever(autoreverses: true), value: dim)
            .onAppear { dim = true }
    }
}

/// Amber strip above the header while the stream is being re-established. The
/// whole point of the resilience work is to not go quiet without saying why.
private struct StateNote: View {
    let reason: ReconnectReason

    var body: some View {
        HStack(spacing: 7) {
            ProgressView()
                .controlSize(.mini)
            Text(message)
                .font(.system(size: 11.5))
        }
        .foregroundStyle(Theme.idle)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.idle.opacity(0.14))
    }

    private var message: String {
        switch reason {
        case .wake: "Getting back to the live stream…"
        case .networkReturned: "Network is back, reconnecting…"
        case .stalled, .failed, .watchdog: "Reconnecting…"
        }
    }
}

private struct Footer: View {
    @Bindable var state: AppState
    let mode: PanelMode
    @State private var startsAtLogin = false

    /// Saving from a global hotkey is invisible otherwise — the panel may not
    /// even be open when it happens.
    private var keepTitle: String {
        guard let saved = state.justSaved else { return "Keep this moment" }
        return saved.duration > 0
            ? "Kept \(Int(saved.duration.rounded()))s"
            : "Kept"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let message = state.momentError {
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.signal)
                    .padding(.horizontal, 6)
                    .padding(.bottom, 3)
            }
            // Keeping a moment acts on what is playing, which the moments list
            // is not about — it would only ever be a dead row there.
            if mode == .stations {
                Button(action: state.saveMoment) {
                    FooterRow(
                        icon: state.justSaved == nil ? "bookmark" : "checkmark",
                        title: keepTitle,
                        key: state.justSaved == nil ? "⌥⌘M" : "",
                        enabled: state.canSaveMoment
                    )
                }
                .buttonStyle(.plain)
                .disabled(!state.canSaveMoment)
            }
            Button(action: state.cycleSleepTimer) {
                SleepRow(state: state)
            }
            .buttonStyle(.plain)
            Button {
                startsAtLogin.toggle()
            } label: {
                FooterRow(
                    icon: startsAtLogin ? "checkmark.square.fill" : "square",
                    title: "Start at login",
                    key: "",
                    enabled: true
                )
            }
            .buttonStyle(.plain)
            if let message = state.loginItemError {
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.signal)
                    .padding(.horizontal, 6)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                FooterRow(icon: "power", title: "Quit Skywave", key: "", enabled: true)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        // Read once on appear, since the system owns the real value.
        .onAppear { startsAtLogin = state.startsAtLogin }
        .onChange(of: startsAtLogin) { _, enabled in
            state.setStartsAtLogin(enabled)
            startsAtLogin = state.startsAtLogin
        }
    }
}

/// Both footer rows share this exactly, so their icons and text line up by
/// construction rather than by tuning.
private struct FooterRow: View {
    let icon: String
    let title: String
    let key: String
    let enabled: Bool

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .frame(width: 16, alignment: .center)
            Text(title)
            Spacer(minLength: 8)
            Text(key)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .font(.system(size: 12.5))
        .foregroundStyle(enabled ? AnyShapeStyle(.primary.opacity(0.75)) : AnyShapeStyle(.tertiary))
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
        .background(isHovered && enabled ? Color.primary.opacity(0.07) : .clear, in: .rect(cornerRadius: 6))
        .onHover { isHovered = $0 }
    }
}

/// The mockup's switch: a neutral track with a raised pill, not the system
/// segmented control, which paints the selection in the accent colour and would
/// compete with the red that means "playing".
private struct ModeSwitch: View {
    @Binding var mode: PanelMode

    var body: some View {
        HStack(spacing: 2) {
            ForEach(PanelMode.allCases) { option in
                let isOn = option == mode
                Button {
                    mode = option
                } label: {
                    Text(option.rawValue)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(isOn ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 3.5)
                        .background {
                            if isOn {
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .fill(.background.opacity(0.9))
                                    .shadow(color: .black.opacity(0.25), radius: 1, y: 1)
                            }
                        }
                        // Without this the hit area is the text itself, and the
                        // rest of the pill does nothing when clicked.
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(.primary.opacity(0.07), in: .rect(cornerRadius: 7))
    }
}


/// One row for the whole sleep timer: clicking walks 15 → 30 → 60 → 90 → off.
///
/// The countdown redraws through `TimelineView`, so ticking costs no observable
/// state and the rest of the panel is not rebuilt once a second.
private struct SleepRow: View {
    @Bindable var state: AppState

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            FooterRow(
                icon: state.sleepUntil == nil ? "moon" : "moon.fill",
                title: title(at: context.date),
                key: "",
                enabled: true
            )
        }
    }

    private func title(at now: Date) -> String {
        guard let until = state.sleepUntil else { return "Sleep timer" }
        return "Sleeps in " + Countdown.text(until: until, now: now)
    }
}
