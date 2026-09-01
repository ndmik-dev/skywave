import SwiftUI
import SkywaveKit

/// Favourites first, then the rest — until a query is typed, which flattens the
/// list to whatever matches.
struct StationList: View {
    @Bindable var state: AppState

    @State private var query = ""
    /// Nil until the arrow keys are used: a highlight nobody asked for reads as
    /// a claim about the station, and the panel already has one of those.
    @State private var selection: Int?
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
        // Also on the container, not only on the text field: clicking a row
        // moves focus to that button, and handlers living on the field alone
        // stopped firing from then on. An ancestor still sees the key.
        .modifier(KeyNavigation(list: self))
    }

    private var search: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.tertiary)
                .font(.callout)
            TextField("Search", text: $query)
                .textFieldStyle(.plain)
                .focused($searchFocused)
                // The field consumes arrows for its own insertion point, so it
                // needs the handlers too — the ancestor never sees those keys.
                .modifier(KeyNavigation(list: self))
                // While searching, the top match is the obvious target for
                // Enter, so the cursor is worth showing unasked.
                .onChange(of: query) { _, text in
                    selection = text.trimmingCharacters(in: .whitespaces).isEmpty ? nil : 0
                }
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
                        Text("Nothing matches")
                            .font(.system(size: 12.5))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                    } else if isSearching {
                        rowGroup(visible)
                    } else {
                        GroupTitle("Favourites")
                        rowGroup(state.stations.filter(\.favorite))
                        let rest = state.stations.filter { !$0.favorite }
                        if !rest.isEmpty {
                            Divider().padding(.horizontal, 10).padding(.vertical, 4)
                            GroupTitle("All stations")
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
                guard let index, visible.indices.contains(index) else { return }
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
                isSelected: selection.map { visible.indices.contains($0)
                    && visible[$0].id == station.id } ?? false
            )
            .id(station.id)
        }
    }

    /// The first press lands on the end the key points at: Down on the first
    /// row, Up on the last. It used to jump to whatever was playing, which read
    /// as the arrows skipping half the list.
    func move(_ delta: Int) {
        guard !visible.isEmpty else { return }
        guard let current = selection else {
            selection = delta > 0 ? 0 : visible.count - 1
            return
        }
        // Clamped, not wrapped: wrapping from the last row back to the first is
        // indistinguishable from the cursor vanishing.
        selection = min(max(current + delta, 0), visible.count - 1)
    }

    func playSelected() {
        guard let index = selection, visible.indices.contains(index) else { return }
        state.toggle(visible[index])
        // Clicking or playing must not strand the keyboard: focus goes back to
        // the field so the next arrow press still works.
        searchFocused = true
    }

    func clearQuery() -> Bool {
        guard isSearching else { return false }
        query = ""
        selection = nil
        return true
    }

}

private struct StationRow: View {
    let station: Station
    @Bindable var state: AppState
    /// The row the arrow keys are on, which Enter would play. The mouse never
    /// moves it, so the panel shows at most two marks and they never mean the
    /// same thing: solid red is what is playing, grey is where the keys are.
    let isSelected: Bool

    private var isCurrent: Bool { state.isCurrent(station) }

    /// What the station's API says is on. Twelve stations have no API, and get
    /// no line rather than an invented one.
    private var show: String? {
        guard let playing = state.onAir[station.id] else { return nil }
        if playing.isOffAir { return "off air" }
        return playing.show ?? playing.track
    }

    private var background: Color {
        if isCurrent { return Theme.signal }
        return isSelected ? .primary.opacity(0.09) : .clear
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
                        .foregroundStyle(isCurrent ? AnyShapeStyle(.white.opacity(0.8)) : AnyShapeStyle(.tertiary))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .foregroundStyle(isCurrent ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .padding(.horizontal, 6)
            .padding(.vertical, 6)
            .frame(minHeight: 30)
            .contentShape(.rect)
            .background(background, in: .rect(cornerRadius: 6))
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

/// The arrow/Enter/Escape bindings, applied both to the search field and to the
/// list around it so focus moving between them never leaves the keyboard dead.
private struct KeyNavigation: ViewModifier {
    let list: StationList

    func body(content: Content) -> some View {
        content
            .onKeyPress(.upArrow) { list.move(-1); return .handled }
            .onKeyPress(.downArrow) { list.move(1); return .handled }
            .onKeyPress(.return) { list.playSelected(); return .handled }
            .onKeyPress(.escape) {
                // First Escape clears the query, a second closes the panel.
                list.clearQuery() ? .handled : .ignored
            }
    }
}
