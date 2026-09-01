import SwiftUI
import SkywaveKit

/// Favourites first, then the rest — until a query is typed, which flattens the
/// list to whatever matches.
struct StationList: View {
    @Bindable var state: AppState

    @State private var query = ""
    @State private var selection = 0
    @FocusState private var searchFocused: Bool

    /// Rows carry a second line only for the eight polled stations, so the height
    /// is measured from the tallest.
    private static let rowHeight: CGFloat = 34
    private static let maxHeight: CGFloat = 380

    /// City is not shown any more, but it is still worth searching by.
    private var matches: [Station] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }
        return state.stations.filter {
            $0.name.localizedCaseInsensitiveContains(trimmed)
                || $0.city.localizedCaseInsensitiveContains(trimmed)
                || (state.onAir[$0.id]?.show?.localizedCaseInsensitiveContains(trimmed) ?? false)
        }
    }

    private var isSearching: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }

    /// The list in the order it is drawn, which is what the arrow keys walk.
    private var visible: [Station] {
        isSearching
            ? matches
            : state.stations.filter(\.favorite) + state.stations.filter { !$0.favorite }
    }

    private var height: CGFloat {
        min(CGFloat(max(visible.count, 1)) * Self.rowHeight + 17, Self.maxHeight)
    }

    var body: some View {
        VStack(spacing: 0) {
            search
            Divider()
            rows
        }
    }

    private var search: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.tertiary)
                .font(.callout)
            TextField("Search", text: $query)
                .textFieldStyle(.plain)
                .focused($searchFocused)
                .onKeyPress(.upArrow) { move(-1); return .handled }
                .onKeyPress(.downArrow) { move(1); return .handled }
                .onKeyPress(.return) { playSelected(); return .handled }
                .onKeyPress(.escape) {
                    // First Escape clears the query, a second closes the panel.
                    guard isSearching else { return .ignored }
                    query = ""
                    return .handled
                }
                .onChange(of: query) { _, _ in selection = 0 }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .onAppear { searchFocused = true }
    }

    private var rows: some View {
        ScrollViewReader { scroller in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if visible.isEmpty {
                        Text("Nothing matches")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                    } else if isSearching {
                        rowGroup(visible)
                    } else {
                        rowGroup(state.stations.filter(\.favorite))
                        let rest = state.stations.filter { !$0.favorite }
                        if !rest.isEmpty {
                            Divider().padding(.vertical, 4)
                            rowGroup(rest)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            // A ScrollView reports an ideal height of zero, and MenuBarExtra sizes
            // its window to the ideal — without this the list collapses.
            .frame(height: height)
            .onChange(of: selection) { _, index in
                guard visible.indices.contains(index) else { return }
                withAnimation(.easeOut(duration: 0.1)) {
                    scroller.scrollTo(visible[index].id, anchor: .center)
                }
            }
        }
    }

    private func rowGroup(_ stations: [Station]) -> some View {
        ForEach(stations) { station in
            StationRow(
                station: station,
                state: state,
                isSelected: visible.indices.contains(selection)
                    && visible[selection].id == station.id
            )
            .id(station.id)
        }
    }

    private func move(_ delta: Int) {
        guard !visible.isEmpty else { return }
        selection = (selection + delta + visible.count) % visible.count
    }

    private func playSelected() {
        guard visible.indices.contains(selection) else { return }
        state.toggle(visible[selection])
    }
}

private struct StationRow: View {
    let station: Station
    @Bindable var state: AppState
    /// The one row Enter would play. Moved by the arrow keys only — the mouse
    /// deliberately does not highlight anything, so there is never more than one
    /// mark on screen and it always means the same thing.
    let isSelected: Bool

    private var isCurrent: Bool { state.isCurrent(station) }

    /// What is on air, when the station's API says. The twelve ICY and HLS
    /// stations reveal nothing until they are playing.
    private var subtitle: String? {
        guard let playing = state.onAir[station.id] else { return nil }
        if playing.isOffAir { return "Off air" }
        return playing.show ?? playing.track
    }

    var body: some View {
        Button {
            state.toggle(station)
        } label: {
            HStack(spacing: 8) {
                indicator
                VStack(alignment: .leading, spacing: 1) {
                    Text(station.name)
                        .fontWeight(isCurrent ? .semibold : .regular)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .contentShape(.rect)
            .background(background, in: .rect(cornerRadius: 5))
        }
        .buttonStyle(.plain)
    }

    /// Marks the station that is on air, and nothing else. The frame is reserved
    /// either way so names do not shift when playback starts.
    private var indicator: some View {
        Group {
            if isCurrent {
                Image(systemName: "speaker.wave.2.fill")
                    .foregroundStyle(.tint)
            }
        }
        .frame(width: 14)
    }

    private var background: Color {
        isSelected ? .primary.opacity(0.12) : .clear
    }
}
