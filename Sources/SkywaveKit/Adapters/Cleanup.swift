import Foundation

/// Station APIs are messy in consistent ways: Airtime and NTS HTML-escape their
/// titles, Airtime leaves the source filename in the track name, and several
/// stations leave a dangling separator when the artist field is blank.
public enum Cleanup {
    /// - Returns: `nil` when nothing readable is left.
    public static func title(_ raw: String?) -> String? {
        guard let raw else { return nil }
        var text = decodeEntities(raw)
        text = dropAudioExtension(text)
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // A blank artist field leaves the separator behind: " - Some Show".
        while text.hasPrefix("-") || text.hasPrefix("–") {
            text = String(text.dropFirst()).trimmingCharacters(in: .whitespaces)
        }
        while text.hasSuffix("-") || text.hasSuffix("–") {
            text = String(text.dropLast()).trimmingCharacters(in: .whitespaces)
        }
        text = text.split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
        return text.isEmpty ? nil : text
    }

    /// Joins artist and title, tolerating either being absent or blank.
    public static func track(artist: String?, title: String?) -> String? {
        let artist = self.title(artist)
        let title = self.title(title)
        return switch (artist, title) {
        case let (artist?, title?): "\(artist) — \(title)"
        default: title ?? artist
        }
    }

    private static let namedEntities = [
        "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"",
        "&apos;": "'", "&nbsp;": " ",
    ]

    /// Handles the named entities these APIs actually emit plus numeric refs.
    /// Deliberately not `NSAttributedString(html:)`, which is main-thread-bound
    /// and far too slow for a value polled every few seconds.
    public static func decodeEntities(_ raw: String) -> String {
        guard raw.contains("&") else { return raw }
        var text = raw
        for (entity, replacement) in namedEntities {
            text = text.replacingOccurrences(of: entity, with: replacement, options: .caseInsensitive)
        }
        guard text.contains("&#") else { return text }

        var output = ""
        var rest = Substring(text)
        while let start = rest.range(of: "&#"),
              let end = rest[start.upperBound...].firstIndex(of: ";") {
            let digits = rest[start.upperBound..<end]
            let isHex = digits.first == "x" || digits.first == "X"
            let number = isHex ? digits.dropFirst() : digits
            guard let code = UInt32(number, radix: isHex ? 16 : 10),
                  let scalar = Unicode.Scalar(code) else {
                output += rest[..<end]
                rest = rest[end...]
                continue
            }
            output += rest[..<start.lowerBound]
            output.unicodeScalars.append(scalar)
            rest = rest[rest.index(after: end)...]
        }
        return output + rest
    }

    private static let audioExtensions: Set<String> = ["mp3", "m4a", "aac", "wav", "flac", "ogg", "aiff"]

    private static func dropAudioExtension(_ text: String) -> String {
        guard let dot = text.lastIndex(of: "."), dot != text.startIndex else { return text }
        let ext = text[text.index(after: dot)...].lowercased()
        return audioExtensions.contains(ext) ? String(text[..<dot]) : text
    }
}
