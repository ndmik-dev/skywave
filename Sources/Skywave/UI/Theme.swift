import SwiftUI
import SkywaveKit

/// The panel's visual language, taken from the "Ефір" mockups.
enum Theme {
    /// Selection, the play button, waveforms — the one accent the panel uses.
    static let signal = Color(red: 0xD8 / 255, green: 0x44 / 255, blue: 0x2E / 255)
    static let onAir = Color(red: 0x37 / 255, green: 0xC2 / 255, blue: 0x6B / 255)
    static let idle = Color(red: 0xD2 / 255, green: 0xA0 / 255, blue: 0x3C / 255)
    static let offAir = Color(red: 0x8E / 255, green: 0x8E / 255, blue: 0x93 / 255)

    static let width: CGFloat = 344
}

/// A station's tile: a gradient with its initial, coloured from its id so the
/// same station always looks the same.
struct Artwork: View {
    let station: Station
    var size: CGFloat = 46

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.17, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [shade(0.52), shade(0.34)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: size, height: size)
            .overlay(
                Text(initial)
                    .font(.system(size: size * 0.37, weight: .bold))
                    .foregroundStyle(.white)
            )
    }

    private var initial: String {
        String(station.name.first.map(String.init)?.uppercased() ?? "·")
    }

    /// Stable hue per station — `hashValue` is salted per process and would give
    /// a station a different colour on every launch.
    private var hue: Double {
        var hash: UInt64 = 5381
        for byte in station.id.utf8 { hash = hash &* 33 &+ UInt64(byte) }
        return Double(hash % 360) / 360
    }

    private func shade(_ brightness: Double) -> Color {
        Color(hue: hue, saturation: 0.62, brightness: brightness)
    }
}

/// The small coloured dot that says whether a station is on air.
///
/// Absent when the station has no API to ask — inventing a green dot for the
/// twelve that report nothing would be a lie.
struct StatusDot: View {
    let playing: NowPlaying?

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 6, height: 6)
    }

    private var color: Color {
        guard let playing else { return .secondary.opacity(0.25) }
        if playing.isOffAir { return Theme.offAir }
        return playing.isEmpty ? Theme.idle : Theme.onAir
    }
}
