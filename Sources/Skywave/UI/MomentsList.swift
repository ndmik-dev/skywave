import SwiftUI
import SkywaveKit

/// Everything kept so far, newest first. Opens in the Finder rather than
/// playing in-app: these are ordinary files in ~/Music/Skywave.
struct MomentsList: View {
    @Bindable var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if state.moments.isEmpty {
                Text("No moments kept yet")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(state.moments) { moment in
                            MomentRow(moment: moment, state: state)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(height: min(CGFloat(state.moments.count) * 38 + 8, 300))
            }
        }
        .task { await state.refreshMoments() }
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
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(moment.title ?? moment.stationName)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if isHovered {
                    Button {
                        state.delete(moment)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help("Delete")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .contentShape(.rect)
            .background(isHovered ? Color.primary.opacity(0.07) : .clear, in: .rect(cornerRadius: 5))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }

    private var subtitle: String {
        let when = moment.capturedAt.formatted(date: .abbreviated, time: .shortened)
        let length = moment.duration > 0 ? " · \(Int(moment.duration.rounded()))s" : ""
        // The title line already carries the show, so name the station here.
        return moment.title == nil ? "\(when)\(length)" : "\(moment.stationName) · \(when)\(length)"
    }
}
