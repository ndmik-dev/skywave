import SwiftUI
import SkywaveKit

enum PanelMode: String, CaseIterable, Identifiable {
    case stations = "Станції"
    case moments = "Моменти"

    var id: String { rawValue }
}

struct PanelView: View {
    @Bindable var state: AppState
    @State private var mode: PanelMode = .stations

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let message = state.fatalError {
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
                case .moments: MomentsList(state: state)
                }
                Divider()
                Footer(state: state)
            }
        }
        .frame(width: Theme.width)
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
                    Text(state.current?.name ?? "Нічого не грає")
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                    Text(showLine)
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
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
                Spacer(minLength: 0)

                if state.current != nil {
                    Button(action: state.stop) {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.white)
                            .frame(width: 34, height: 34)
                            .background(Theme.signal, in: .circle)
                    }
                    .buttonStyle(.plain)
                    .help("Зупинити")
                }
            }

            Picker("", selection: $mode) {
                ForEach(PanelMode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.top, 12)
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }

    private var showLine: String {
        guard let station = state.current else { return "Обери станцію" }
        if state.isLoading { return "з'єднання…" }
        return state.nowPlaying.isOffAir
            ? "не в ефірі"
            : state.nowPlaying.show ?? station.city
    }

    /// The track when the station reports one, otherwise just that it is on.
    private var trackLine: String {
        guard let station = state.current else { return "⌥⌘P" }
        if let track = state.nowPlaying.track { return track }
        return state.isPlaying ? "в ефірі · \(station.city)" : station.city
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
        case .wake: "Повертаюсь до живого ефіру…"
        case .networkReturned: "Мережа повернулась, під'єднуюсь…"
        case .stalled, .failed, .watchdog: "З'єднання відновлюється…"
        }
    }
}

private struct Footer: View {
    @Bindable var state: AppState
    @State private var startsAtLogin = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let message = state.momentError {
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.signal)
                    .padding(.horizontal, 6)
                    .padding(.bottom, 3)
            }
            FooterRow(
                icon: "bookmark",
                title: "Зберегти момент",
                key: "⌥⌘M",
                enabled: state.canSaveMoment,
                action: state.saveMoment
            )
            Menu {
                Toggle("Запускати при вході", isOn: $startsAtLogin)
                if let message = state.loginItemError {
                    Text(message)
                }
                Divider()
                Button("Вийти з Skywave") { NSApplication.shared.terminate(nil) }
            } label: {
                FooterRow(icon: "gearshape", title: "Налаштування…", key: "", enabled: true, action: nil)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .onAppear { startsAtLogin = state.startsAtLogin }
        .onChange(of: startsAtLogin) { _, enabled in
            state.setStartsAtLogin(enabled)
            startsAtLogin = state.startsAtLogin
        }
    }
}

private struct FooterRow: View {
    let icon: String
    let title: String
    let key: String
    let enabled: Bool
    let action: (() -> Void)?

    @State private var isHovered = false

    var body: some View {
        let row = HStack(spacing: 9) {
            Image(systemName: icon)
                .frame(width: 14)
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
        .contentShape(.rect)
        .background(isHovered && enabled ? Color.primary.opacity(0.07) : .clear, in: .rect(cornerRadius: 6))
        .onHover { isHovered = $0 }

        if let action {
            Button(action: action) { row }
                .buttonStyle(.plain)
                .disabled(!enabled)
        } else {
            row
        }
    }
}
