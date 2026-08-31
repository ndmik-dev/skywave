import SwiftUI
import SkywaveKit

struct PanelView: View {
    @Bindable var state: AppState

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
                StationList(state: state)
                Divider()
                Footer(state: state)
            }
        }
        .frame(width: 300)
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
                    Button(action: state.stop) {
                        Image(systemName: "stop.fill")
                    }
                    .buttonStyle(.borderless)
                    .help("Stop")
                }
                Text(subtitle(for: station))
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

    private func subtitle(for station: Station) -> String {
        if state.reconnecting != nil { return "Reconnecting…" }
        if state.isLoading { return "Connecting…" }
        if state.nowPlaying.isOffAir { return "Off air" }
        let lines = [state.nowPlaying.show, state.nowPlaying.track].compactMap { $0 }
        // Several stations never report anything; the city is better than blank.
        return lines.isEmpty ? station.city : lines.joined(separator: " · ")
    }
}

private struct Footer: View {
    @Bindable var state: AppState
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
                Toggle("Start at login", isOn: $startsAtLogin)
                    .toggleStyle(.checkbox)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
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
