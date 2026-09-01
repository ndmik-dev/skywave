import Foundation

/// Formats the sleep timer's remaining time.
///
/// Ceiling rather than rounding: rounding shows the starting value for the first
/// half second and then a trailing `0:00` for a timer that has already fired.
public enum Countdown {
    public static func text(until: Date, now: Date) -> String {
        let left = max(0, Int(until.timeIntervalSince(now).rounded(.up)))
        return String(format: "%d:%02d", left / 60, left % 60)
    }
}
