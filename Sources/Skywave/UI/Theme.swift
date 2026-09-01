import AppKit
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

/// A station's tile: its own mark where one exists, otherwise a gradient with
/// its initial, coloured from its id so the same station always looks the same.
///
/// Eighteen of the twenty ship a logo. SWU FM has no site of its own — swu.fm
/// redirects onto Rinse, and using Rinse's mark would name the wrong station —
/// and Radio Alhara's site carries no icon at all.
struct Artwork: View {
    let station: Station
    var size: CGFloat = 46

    var body: some View {
        Group {
            if let logo = station.logoURL, let image = NSImage(contentsOf: logo) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
            } else {
                LinearGradient(
                    colors: [shade(0.52), shade(0.34)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .overlay(
                    Text(initial)
                        .font(.system(size: size * 0.37, weight: .bold))
                        .foregroundStyle(.white)
                )
            }
        }
        .frame(width: size, height: size)
        .clipShape(.rect(cornerRadius: size * 0.17, style: .continuous))
        .accessibilityHidden(true)
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

/// Whether a station is on air.
///
/// Filled means the station's API answered: green on air, amber answering but
/// with no title, grey off air. An outline means there is no API to ask — the
/// twelve ICY and HLS stations say nothing about themselves, and a filled dot
/// there would be an invention.
struct StatusDot: View {
    let playing: NowPlaying?
    var unreachable = false

    var body: some View {
        Group {
            if unreachable {
                Circle().fill(Theme.offAir)
            } else if let playing {
                Circle().fill(color(playing))
            } else {
                Circle().strokeBorder(.tertiary, lineWidth: 1)
            }
        }
        .frame(width: 6, height: 6)
        // Decoration: the row's own label already says the state in words.
        .accessibilityHidden(true)
    }

    private func color(_ playing: NowPlaying) -> Color {
        if playing.isOffAir { return Theme.offAir }
        return playing.isEmpty ? Theme.idle : Theme.onAir
    }
}
