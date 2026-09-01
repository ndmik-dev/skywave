import Foundation
import os

/// A fixed 60-second window of the most recent audio, always being overwritten.
///
/// Written from the audio render thread and read from the main one. The writer
/// only ever *tries* the lock: dropping a few milliseconds when a save is in
/// progress is far better than making the audio thread wait.
public final class RingBuffer: @unchecked Sendable {
    public let sampleRate: Double
    public let channels: Int
    /// Frames the buffer can hold, i.e. `seconds × sampleRate`.
    public let capacity: Int

    private let storage: UnsafeMutablePointer<Float>
    private var writeIndex = 0
    private var filled = 0
    private let lock = OSAllocatedUnfairLock()

    public init(seconds: Double, sampleRate: Double, channels: Int) {
        self.sampleRate = sampleRate
        self.channels = channels
        self.capacity = Int(seconds * sampleRate)
        storage = .allocate(capacity: capacity * channels)
        storage.initialize(repeating: 0, count: capacity * channels)
    }

    deinit {
        storage.deallocate()
    }

    /// Seconds of audio currently held, up to the capacity.
    public var duration: TimeInterval {
        lock.withLock { Double(filled) / sampleRate }
    }

    /// Appends interleaved frames. Called on the audio thread.
    public func write(interleaved source: UnsafePointer<Float>, frames: Int) {
        guard frames > 0, lock.lockIfAvailable() else { return }
        defer { lock.unlock() }

        var remaining = frames
        var offset = 0
        while remaining > 0 {
            let chunk = min(remaining, capacity - writeIndex)
            storage.advanced(by: writeIndex * channels)
                .update(from: source.advanced(by: offset * channels), count: chunk * channels)
            writeIndex = (writeIndex + chunk) % capacity
            offset += chunk
            remaining -= chunk
        }
        filled = min(filled + frames, capacity)
    }

    /// Copies out everything held, oldest frame first.
    public func snapshot() -> [Float] {
        lock.withLock {
            guard filled > 0 else { return [] }
            var output = [Float](repeating: 0, count: filled * channels)
            // The oldest frame sits just after the write head once wrapped.
            let start = filled == capacity ? writeIndex : 0
            output.withUnsafeMutableBufferPointer { out in
                guard let base = out.baseAddress else { return }
                let firstRun = min(filled, capacity - start)
                base.update(from: storage.advanced(by: start * channels), count: firstRun * channels)
                if firstRun < filled {
                    base.advanced(by: firstRun * channels)
                        .update(from: storage, count: (filled - firstRun) * channels)
                }
            }
            return output
        }
    }

    public func reset() {
        lock.withLock {
            writeIndex = 0
            filled = 0
        }
    }
}
