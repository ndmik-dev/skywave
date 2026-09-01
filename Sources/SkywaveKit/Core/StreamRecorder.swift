import Foundation
import os

/// Keeps the last minute of a station on hand, over its own connection.
///
/// It stores the broadcast bytes exactly as they arrive and never decodes them.
/// Saving a moment is then a copy, not a re-encode: bit-identical to what went
/// out, and none of the CoreAudio machinery a PCM pipeline would need.
///
/// The player's own audio cannot be used for this — `MTAudioProcessingTap`
/// yields nothing on 15 of the catalog's 20 stations.
public final class StreamRecorder: NSObject, @unchecked Sendable {
    /// How much history to keep.
    public let seconds: TimeInterval

    private let lock = OSAllocatedUnfairLock()
    /// Timestamped so the window is exactly `seconds` whatever the bitrate is,
    /// including variable ones.
    private var chunks: [(at: ContinuousClock.Instant, data: Data)] = []
    private var contentType = ""
    private var session: URLSession?
    private var task: URLSessionDataTask?
    /// The URL to hold, while it is wanted. Nil once stopped, which is how a
    /// finished request tells a deliberate stop from a dropped connection.
    private var wanted: URL?
    private var retry: Task<Void, Never>?

    public init(seconds: TimeInterval = 60) {
        self.seconds = seconds
        super.init()
    }

    public var isRunning: Bool {
        lock.withLock { wanted != nil }
    }

    public func start(url: URL) {
        stop()
        lock.withLock { wanted = url }
        connect(to: url)
    }

    private func connect(to url: URL) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)

        // No `Icy-MetaData` header: metadata would be interleaved into the audio
        // and corrupt anything saved from it.
        let task = session.dataTask(with: URLRequest(url: url))
        lock.withLock {
            self.session = session
            self.task = task
        }
        task.resume()
    }

    public func stop() {
        retry?.cancel()
        retry = nil
        let (task, session) = lock.withLock {
            defer {
                self.task = nil
                self.session = nil
                self.wanted = nil
                chunks.removeAll()
            }
            return (self.task, self.session)
        }
        task?.cancel()
        session?.invalidateAndCancel()
    }

    /// The capture connection is separate from the player's, so it can die on
    /// its own while playback carries on — and then a moment would quietly hold
    /// nothing but stale audio. Reconnects until told to stop.
    private func reconnect() {
        guard let url = lock.withLock({ wanted }) else { return }
        retry?.cancel()
        retry = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled, let self,
                  self.lock.withLock({ self.wanted }) == url else { return }
            self.connect(to: url)
        }
    }

    /// The held audio, oldest byte first, with the extension its codec calls for.
    ///
    /// Usually holds rather more than `seconds`: Icecast sends several seconds of
    /// pre-buffer the moment you connect, so the bytes that arrive in the first
    /// instant already cover a stretch of airtime. The window is trimmed by
    /// arrival time, which bounds memory; the real duration is read from the
    /// finished file.
    ///
    /// - Returns: `nil` when nothing has been captured yet.
    public func snapshot() -> (data: Data, fileExtension: String)? {
        lock.withLock {
            trimLocked()
            guard !chunks.isEmpty else { return nil }
            var data = Data()
            data.reserveCapacity(chunks.reduce(0) { $0 + $1.data.count })
            for chunk in chunks { data.append(chunk.data) }

            let isAAC = contentType.contains("aac")
            // The window opens mid-frame. Players tolerate that, but converters
            // do not: afconvert refuses an ADTS file whose first bytes are the
            // tail of a frame, so the leading partial frame is dropped.
            if let start = Self.firstFrame(in: data, isAAC: isAAC), start > 0 {
                data = data.subdata(in: start..<data.count)
            }
            return (data, isAAC ? "aac" : "mp3")
        }
    }

    /// Offset of the first whole audio frame.
    ///
    /// For ADTS the candidate is confirmed by checking that the frame it declares
    /// lands on another sync word — a lone 0xFFF can easily be payload.
    private static func firstFrame(in data: Data, isAAC: Bool) -> Int? {
        let bytes = [UInt8](data.prefix(64 * 1024))
        guard bytes.count > 8 else { return nil }
        for index in 0..<(bytes.count - 8) {
            guard bytes[index] == 0xFF else { continue }
            if isAAC {
                guard bytes[index + 1] & 0xF6 == 0xF0 else { continue }
                let length = (Int(bytes[index + 3] & 0x03) << 11)
                    | (Int(bytes[index + 4]) << 3)
                    | (Int(bytes[index + 5]) >> 5)
                let next = index + length
                guard length > 7, next + 1 < bytes.count,
                      bytes[next] == 0xFF, bytes[next + 1] & 0xF6 == 0xF0 else { continue }
                return index
            }
            // MPEG audio: eleven sync bits, and neither the layer nor the
            // bitrate field may be the reserved value.
            guard bytes[index + 1] & 0xE0 == 0xE0,
                  bytes[index + 1] & 0x06 != 0x00,
                  bytes[index + 2] & 0xF0 != 0xF0 else { continue }
            return index
        }
        return nil
    }

    private func trimLocked() {
        let cutoff = ContinuousClock.now - .seconds(seconds)
        guard let keepFrom = chunks.firstIndex(where: { $0.at >= cutoff }) else {
            chunks.removeAll()
            return
        }
        chunks.removeFirst(keepFrom)
    }
}

extension StreamRecorder: URLSessionDataDelegate {
    public func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        let type = (response as? HTTPURLResponse)?
            .value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? ""
        lock.withLock { contentType = type }
        completionHandler(.allow)
    }

    public func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive data: Data
    ) {
        lock.withLock {
            chunks.append((ContinuousClock.now, data))
            trimLocked()
        }
    }

    public func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: (any Error)?
    ) {
        // An endless stream only ends by failing, so any completion while the
        // recorder is still wanted means the connection dropped. Held audio is
        // kept: a gap is better than losing the last minute entirely.
        reconnect()
    }
}

private extension Duration {
    var seconds: TimeInterval {
        TimeInterval(components.seconds) + TimeInterval(components.attoseconds) / 1e18
    }
}
