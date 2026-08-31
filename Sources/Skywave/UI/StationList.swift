import SwiftUI
import SkywaveKit

/// Favourites first, then the rest, in catalog order.
struct StationList: View {
    @Bindable var state: AppState

    /// A ScrollView reports an ideal height of zero, and MenuBarExtra sizes its
    /// window to the ideal — so without an explicit height the list collapses.
    private static let rowHeight: CGFloat = 27
    private static let maxHeight: CGFloat = 380

    private var height: CGFloat {
        let rows = CGFloat(state.stations.count) * Self.rowHeight
        return min(rows + 17, Self.maxHeight)
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(state.stations.filter(\.favorite)) { station in
                    StationRow(station: station, state: state)
                }
                let rest = state.stations.filter { !$0.favorite }
                if !rest.isEmpty {
                    Divider().padding(.vertical, 4)
                    ForEach(rest) { station in
                        StationRow(station: station, state: state)
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .frame(height: height)
    }
}

private struct StationRow: View {
    let station: Station
    @Bindable var state: AppState
    @State private var isHovered = false

    private var isCurrent: Bool { state.isCurrent(station) }

    var body: some View {
        Button {
            state.toggle(station)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isCurrent ? "speaker.wave.2.fill" : "circle.dotted")
                    .foregroundStyle(isCurrent ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                    .frame(width: 16)
                Text(station.name)
                    .fontWeight(isCurrent ? .semibold : .regular)
                Spacer(minLength: 8)
                Text(station.city)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .contentShape(.rect)
            .background(isHovered ? Color.primary.opacity(0.07) : .clear, in: .rect(cornerRadius: 5))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
