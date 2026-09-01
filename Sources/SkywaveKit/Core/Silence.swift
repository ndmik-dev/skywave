import Foundation

/// Puts "how long since this station was heard" into words.
///
/// Deliberately coarse: the useful question is whether a station went quiet
/// this morning or last year, never whether it was 4 or 5 hours ago.
public enum Silence {
    public static func text(since: Date?, now: Date = Date()) -> String {
        guard let since else { return "never heard" }
        let seconds = now.timeIntervalSince(since)
        switch seconds {
        case ..<3600: return "heard just now"
        case ..<86_400: return "heard \(Int(seconds / 3600))h ago"
        case ..<(86_400 * 14): return "heard \(Int(seconds / 86_400))d ago"
        default:
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM yyyy"
            return "last heard \(formatter.string(from: since))"
        }
    }
}
