import SwiftUI
import SkywaveKit

/// Everything kept so far, newest first. These are ordinary files in
/// ~/Music/Skywave, so a click reveals them in the Finder rather than playing
/// them in a player the app does not have.
struct MomentsList: View {
    @Bindable var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Моменти")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text(count)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 4)

            if state.moments.isEmpty {
                Text("Поки нічого не збережено")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(state.moments) { moment in
                            MomentRow(moment: moment, state: state)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 6)
                }
                .frame(height: min(CGFloat(state.moments.count) * 48 + 6, 320))
            }
        }
    }

    private var count: String {
        state.moments.isEmpty ? "" : "\(state.moments.count) збережено"
    }
}

private struct MomentRow: View {
    let moment: Moment
    @Bindable var state: AppState
    @State private var isHovered = false

    var body: some View {
        Button {
            state.reveal(moment)
        } label: {
            HStack(spacing: 11) {
                Waveform(seed: moment.id)
                VStack(alignment: .leading, spacing: 2) {
                    Text(moment.title ?? moment.stationName)
                        .font(.system(size: 12.5, weight: .semibold))
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if isHovered {
                    Button {
                        state.delete(moment)
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help("Видалити")
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 9)
            .contentShape(.rect)
            .background(isHovered ? Color.primary.opacity(0.07) : .clear, in: .rect(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }

    private var subtitle: String {
        let when = moment.capturedAt.formatted(date: .abbreviated, time: .shortened)
        let length = moment.duration > 0 ? " · \(Int(moment.duration.rounded())) с" : ""
        // The first line already carries the show when there was one.
        return moment.title == nil ? "\(when)\(length)" : "\(moment.stationName) · \(when)\(length)"
    }
}

/// Decorative, not an analysis of the audio — but stable per moment, so a given
/// clip always looks like itself rather than reshuffling on every redraw.
private struct Waveform: View {
    let seed: String

    var body: some View {
        HStack(alignment: .center, spacing: 1.5) {
            ForEach(Array(bars.enumerated()), id: \.offset) { _, height in
                Capsule()
                    .fill(Theme.signal.opacity(0.85))
                    .frame(width: 2, height: height)
            }
        }
        .frame(width: 70, height: 30)
    }

    private var bars: [CGFloat] {
        var hash: UInt64 = 5381
        for byte in seed.utf8 { hash = hash &* 33 &+ UInt64(byte) }
        return (0..<20).map { index in
            hash = hash &* 6364136223846793005 &+ 1442695040888963407
            let step = Double((hash >> 33) % 100) / 100
            _ = index
            return 8 + step * 22
        }
    }
}
