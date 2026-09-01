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

    /// Writes held broadcast bytes straight to disk, unmodified.
    ///
    /// No decode and no re-encode: the file is byte-identical to what the
    /// station sent, which is both simpler and better than any transcode.
    public static func save(
        data: Data,
        fileExtension: String,
        station: Station,
        title: String?,
        capturedAt: Date = Date()
    ) async throws -> Moment {
        guard !data.isEmpty else { throw MomentError.nothingCaptured }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let name = filename(station: station, title: title, at: capturedAt) + "." + fileExtension
        let url = directory.appending(path: name)
        try data.write(to: url)

        return Moment(
            url: url,
            stationName: station.name,
            title: title,
            capturedAt: capturedAt,
            duration: await duration(of: url)
        )
    }

    /// Read from the finished file. Accurate now that the data starts on a frame
    /// boundary — before that alignment, the same call was out by 60%.
    private static func duration(of url: URL) async -> TimeInterval {
        guard let time = try? await AVURLAsset(url: url).load(.duration) else { return 0 }
        let seconds = CMTimeGetSeconds(time)
        return seconds.isFinite && seconds > 0 ? seconds : 0
    }

    public static func saved() async -> [Moment] {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        var moments: [Moment] = []
        for url in contents where ["mp3", "aac", "m4a"].contains(url.pathExtension) {
            if let moment = await moment(from: url) { moments.append(moment) }
        }
        return moments.sorted { $0.capturedAt > $1.capturedAt }
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
        return sanitised(parts.joined(separator: " — "))
    }

    /// Rebuilt from the filename, so the folder stays the source of truth and
    /// files stay meaningful if moved out of the app.
    private static func moment(from url: URL) async -> Moment? {
        let name = url.deletingPathExtension().lastPathComponent
        let parts = name.components(separatedBy: " — ")
        guard parts.count >= 2, let date = stamp.date(from: parts[0]) else { return nil }
        let attributes = try? url.resourceValues(forKeys: [.creationDateKey])
        return Moment(
            url: url,
            stationName: parts[1],
            title: parts.count > 2 ? parts[2...].joined(separator: " — ") : nil,
            capturedAt: attributes?.creationDate ?? date,
            duration: await duration(of: url)
        )
    }

    private static func sanitised(_ name: String) -> String {
        name.components(separatedBy: CharacterSet(charactersIn: "/:\\")).joined(separator: "-")
    }
}
