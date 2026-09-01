import SwiftUI
import SkywaveKit

/// Favourites first, then the rest — until a query is typed, which flattens the
/// list to whatever matches.
struct StationList: View {
    @Bindable var state: AppState

    @State private var query = ""
    @State private var selection = 0
    @FocusState private var searchFocused: Bool

    private static let rowHeight: CGFloat = 30
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
            TextField("Пошук", text: $query)
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
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .onAppear { searchFocused = true }
    }

    private var rows: some View {
        ScrollViewReader { scroller in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if visible.isEmpty {
                        Text("Нічого не знайшлося")
                            .font(.system(size: 12.5))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                    } else if isSearching {
                        rowGroup(visible)
                    } else {
                        GroupTitle("Улюблені")
                        rowGroup(state.stations.filter(\.favorite))
                        let rest = state.stations.filter { !$0.favorite }
                        if !rest.isEmpty {
                            Divider().padding(.horizontal, 10).padding(.vertical, 4)
                            GroupTitle("Усі станції")
                            rowGroup(rest)
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
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

    /// What the station's API says is on. Twelve stations have no API, and get
    /// no line rather than an invented one.
    private var show: String? {
        guard let playing = state.onAir[station.id] else { return nil }
        if playing.isOffAir { return "не в ефірі" }
        return playing.show ?? playing.track
    }

    var body: some View {
        Button {
            state.toggle(station)
        } label: {
            HStack(spacing: 9) {
                StatusDot(playing: state.onAir[station.id])
                Text(station.name)
                    .font(.system(size: 13, weight: isCurrent ? .semibold : .medium))
                    .fixedSize()
                Spacer(minLength: 8)
                if let show {
                    Text(show)
                        .font(.system(size: 12))
                        .foregroundStyle(isSelected ? AnyShapeStyle(.white.opacity(0.8)) : AnyShapeStyle(.tertiary))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                if isCurrent {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(Theme.signal))
                }
            }
            .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .padding(.horizontal, 6)
            .padding(.vertical, 6)
            .frame(minHeight: 30)
            .contentShape(.rect)
            .background(isSelected ? Theme.signal : .clear, in: .rect(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }
}

private struct GroupTitle: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 6)
            .padding(.top, 2)
            .padding(.bottom, 5)
    }
}
