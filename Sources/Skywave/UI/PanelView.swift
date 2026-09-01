import SwiftUI
import SkywaveKit

struct PanelView: View {
    @Bindable var state: AppState
    @State private var showingMoments = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let message = state.fatalError {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding()
            } else {
                OnAir(state: state)
                Divider()
                if showingMoments {
                    MomentsList(state: state)
                } else {
                    StationList(state: state)
                }
                Divider()
                Footer(state: state, showingMoments: $showingMoments)
            }
        }
        .frame(width: 300)
        .onAppear { state.startWatchingOnAir() }
        .onDisappear { state.stopWatchingOnAir() }
    }
}

/// The header: what is playing, or an invitation to pick something.
private struct OnAir: View {
    @Bindable var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if let station = state.current {
                HStack(spacing: 6) {
                    Text(station.name).font(.headline)
                    Spacer()
                    if state.canSaveMoment {
                        Button(action: state.saveMoment) {
                            Image(systemName: "bookmark")
                        }
                        .buttonStyle(.borderless)
                        .help("Keep the last minute")
                    }
                    Button(action: state.stop) {
                        Image(systemName: "stop.fill")
                    }
                    .buttonStyle(.borderless)
                    .help("Stop")
                }
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Nothing on air").font(.headline)
                Text("Pick a station · ⌥⌘P").font(.callout).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var subtitle: String {
        if state.reconnecting != nil { return "Reconnecting…" }
        if state.isLoading { return "Connecting…" }
        if state.nowPlaying.isOffAir { return "Off air" }
        let lines = [state.nowPlaying.show, state.nowPlaying.track].compactMap { $0 }
        // Twelve stations never report what is on, so there is nothing to say.
        return lines.isEmpty ? "On air" : lines.joined(separator: " · ")
    }
}

private struct Footer: View {
    @Bindable var state: AppState
    @Binding var showingMoments: Bool
    @State private var startsAtLogin = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let message = state.loginItemError {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }
            HStack {
                Button(showingMoments ? "Stations" : "Moments") {
                    showingMoments.toggle()
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                Spacer()
                Text("⌥⌘P")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer()
                // Settings live behind a menu: the panel is for listening, and
                // these are decided once.
                Menu {
                    Toggle("Start at login", isOn: $startsAtLogin)
                    Divider()
                    Button("Quit Skywave") { NSApplication.shared.terminate(nil) }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        // Read once on appear, since the system owns the real value.
        .onAppear { startsAtLogin = state.startsAtLogin }
        .onChange(of: startsAtLogin) { _, enabled in
            state.setStartsAtLogin(enabled)
            startsAtLogin = state.startsAtLogin
        }
    }
}
