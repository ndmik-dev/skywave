import AVFoundation
import Foundation

/// A saved slice of what was just on air.
public struct Moment: Sendable, Identifiable, Hashable {
    public var id: String { url.lastPathComponent }
    public let url: URL
    public let stationName: String
    /// Whatever the station reported at the time, if anything.
    public let title: String?
    public let capturedAt: Date
    public let duration: TimeInterval
}

public enum MomentError: Error, Sendable {
    case nothingCaptured
    case cannotCapture
}

/// Writes ring-buffer contents to disk and lists what has been kept.
public enum Moments {
    /// `~/Music/Skywave` — a normal folder, so the files are usable outside the app.
    public static var directory: URL {
        let music = FileManager.default.urls(for: .musicDirectory, in: .userDomainMask).first
            ?? URL.homeDirectory.appending(path: "Music")
        return music.appending(path: "Skywave")
    }

    /// Writes the buffer as Apple Lossless in an m4a container.
    ///
    /// Lossless on purpose: the source is already a lossy stream, and re-encoding
    /// it through AAC a second time only adds damage. A minute costs a few MB,
    /// which is nothing for something worth keeping.
    public static func save(
        buffer: RingBuffer,
        station: Station,
        title: String?,
        capturedAt: Date = Date()
    ) throws -> Moment {
        let samples = buffer.snapshot()
        guard !samples.isEmpty else { throw MomentError.nothingCaptured }

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: filename(station: station, title: title, at: capturedAt))

        let channels = AVAudioChannelCount(buffer.channels)
        guard let format = AVAudioFormat(
            standardFormatWithSampleRate: buffer.sampleRate,
            channels: channels
        ) else { throw MomentError.cannotCapture }

        let file = try AVAudioFile(forWriting: url, settings: [
            AVFormatIDKey: kAudioFormatAppleLossless,
            AVSampleRateKey: buffer.sampleRate,
            AVNumberOfChannelsKey: buffer.channels,
            AVEncoderBitDepthHintKey: 16,
        ])

        let frames = samples.count / buffer.channels
        guard let pcm = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(frames)
        ) else { throw MomentError.cannotCapture }
        pcm.frameLength = AVAudioFrameCount(frames)

        // The ring buffer is interleaved; AVAudioPCMBuffer's standard format is not.
        for channel in 0..<buffer.channels {
            guard let destination = pcm.floatChannelData?[channel] else { continue }
            for frame in 0..<frames {
                destination[frame] = samples[frame * buffer.channels + channel]
            }
        }
        try file.write(from: pcm)

        return Moment(
            url: url,
            stationName: station.name,
            title: title,
            capturedAt: capturedAt,
            duration: Double(frames) / buffer.sampleRate
        )
    }

    public static func saved() -> [Moment] {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        return contents
            .filter { $0.pathExtension == "m4a" }
            .compactMap(moment(from:))
            .sorted { $0.capturedAt > $1.capturedAt }
    }

    public static func delete(_ moment: Moment) throws {
        try FileManager.default.removeItem(at: moment.url)
    }

    // MARK: - Naming

    private static let stamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return formatter
    }()

    private static func filename(station: Station, title: String?, at date: Date) -> String {
        let parts = [stamp.string(from: date), station.name, title].compactMap { $0 }
        return sanitised(parts.joined(separator: " — ")) + ".m4a"
    }

    /// Rebuilt from the filename, so the folder stays the source of truth and
    /// files stay meaningful if moved out of the app.
    private static func moment(from url: URL) -> Moment? {
        let name = url.deletingPathExtension().lastPathComponent
        let parts = name.components(separatedBy: " — ")
        guard parts.count >= 2, let date = stamp.date(from: parts[0]) else { return nil }
        let attributes = try? url.resourceValues(forKeys: [.creationDateKey])
        return Moment(
            url: url,
            stationName: parts[1],
            title: parts.count > 2 ? parts[2...].joined(separator: " — ") : nil,
            capturedAt: attributes?.creationDate ?? date,
            duration: 0
        )
    }

    private static func sanitised(_ name: String) -> String {
        name.components(separatedBy: CharacterSet(charactersIn: "/:\\")).joined(separator: "-")
    }
}
