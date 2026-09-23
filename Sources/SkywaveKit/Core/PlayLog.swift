import Foundation

/// Which days each station was actually heard.
///
/// One number per station — days it played, at least once — is what answers
/// whether twenty stations in one place was a real need or a nice idea. It is a
/// measurement, not a feature: nothing in the panel shows it.
///
/// Days, not minutes: minutes reward leaving a stream on while away, and the
/// question is which stations get *chosen*.
public struct PlayLog {
    private static let key = "stationDaysPlayed"

    private let defaults: UserDefaults
    /// Station id → set of day keys, `yyyy-MM-dd` in the local calendar.
    private var days: [String: Set<String>]

    private static let dayFormat: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.dictionary(forKey: Self.key) as? [String: [String]] ?? [:]
        days = stored.mapValues(Set.init)
    }

    public mutating func notePlayed(_ station: Station, on date: Date = Date()) {
        days[station.id, default: []].insert(Self.dayFormat.string(from: date))
        defaults.set(days.mapValues { Array($0).sorted() }, forKey: Self.key)
    }

    /// Days the station played within the last `window` days, counting today.
    public func daysPlayed(_ station: Station, within window: Int = 30, now: Date = Date()) -> Int {
        guard let played = days[station.id], !played.isEmpty else { return 0 }
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .day, value: -(window - 1), to: calendar.startOfDay(for: now))!
        let cutoff = Self.dayFormat.string(from: start)
        // Day keys sort as dates, so a string comparison is a date comparison.
        return played.filter { $0 >= cutoff }.count
    }

    public func daysPlayedEver(_ station: Station) -> Int {
        days[station.id]?.count ?? 0
    }

    /// Distinct days on which anything at all was heard.
    public func activeDays(within window: Int = 30, now: Date = Date()) -> Int {
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .day, value: -(window - 1), to: calendar.startOfDay(for: now))!
        let cutoff = Self.dayFormat.string(from: start)
        return Set(days.values.flatMap { $0 }).filter { $0 >= cutoff }.count
    }
}
