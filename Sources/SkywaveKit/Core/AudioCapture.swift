import AVFoundation
import Foundation
import MediaToolbox

/// Feeds a `RingBuffer` from the player's own audio, via `MTAudioProcessingTap`.
///
/// ⚠️ Measured across the whole catalog: this works on only **5 of 20** stations
/// — both SomaFM streams and the three Radiocult ones. Everywhere else neither
/// `AVAsset` nor `AVPlayerItem` ever exposes an audio track, so there is nothing
/// to attach a tap to, and HLS exposes nothing by design.
///
/// Kept because it is free where it works, but it cannot be what "moments" are
/// built on — that needs its own connection to the stream.
public final class AudioCapture: @unchecked Sendable {
    public private(set) var buffer: RingBuffer?

    private let seconds: Double
    private var tap: MTAudioProcessingTap?
    /// Scratch space for interleaving planar input, grown as needed.
    private var scratch = [Float]()

    public init(seconds: Double = 60) {
        self.seconds = seconds
    }

    /// - Returns: `false` when the item has no audio track to tap, as with HLS.
    @discardableResult
    @MainActor
    public func attach(to item: AVPlayerItem) async -> Bool {
        detach()
        guard let track = await audioTrack(of: item) else { return false }

        var callbacks = MTAudioProcessingTapCallbacks(
            version: kMTAudioProcessingTapCallbacksVersion_0,
            clientInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
            init: tapInit,
            finalize: nil,
            prepare: tapPrepare,
            unprepare: nil,
            process: tapProcess
        )

        var created: MTAudioProcessingTap?
        guard MTAudioProcessingTapCreate(
            kCFAllocatorDefault, &callbacks,
            kMTAudioProcessingTapCreationFlag_PostEffects, &created
        ) == noErr, let created else { return false }
        tap = created

        let parameters = AVMutableAudioMixInputParameters(track: track)
        parameters.audioTapProcessor = created
        let mix = AVMutableAudioMix()
        mix.inputParameters = [parameters]
        item.audioMix = mix
        return true
    }

    /// A live stream exposes no tracks until the item is ready, and how long that
    /// takes varies by station, so this waits rather than asking once.
    @MainActor
    private func audioTrack(of item: AVPlayerItem) async -> AVAssetTrack? {
        for attempt in 0..<40 {
            if item.status == .failed { return nil }
            do {
                let tracks = try await item.asset.loadTracks(withMediaType: .audio)
                if ProcessInfo.processInfo.environment["SKYWAVE_DEBUG"] != nil {
                    print("  [tap] attempt \(attempt): status=\(item.status.rawValue) tracks=\(tracks.count)")
                }
                if let track = tracks.first { return track }
            } catch {
                if ProcessInfo.processInfo.environment["SKYWAVE_DEBUG"] != nil {
                    print("  [tap] attempt \(attempt): \(error)")
                }
            }
            try? await Task.sleep(for: .milliseconds(500))
        }
        return nil
    }

    @MainActor
    public func detach() {
        tap = nil
        buffer = nil
    }

    // MARK: - Audio thread

    fileprivate func prepare(format: AudioStreamBasicDescription) {
        let channels = Int(format.mChannelsPerFrame)
        buffer = RingBuffer(seconds: seconds, sampleRate: format.mSampleRate, channels: channels)
        scratch = [Float](repeating: 0, count: 8192 * channels)
    }

    /// Takes the list by pointer: a copy of `AudioBufferList` is a fixed-size
    /// struct whose trailing buffers do not come with it.
    fileprivate func process(_ list: UnsafeMutablePointer<AudioBufferList>, frames: Int) {
        guard let buffer, frames > 0 else { return }
        let buffers = UnsafeMutableAudioBufferListPointer(list)

        // One buffer means the frames are already interleaved; several means one
        // plane per channel, which the ring buffer needs woven together first.
        if buffers.count == 1 {
            guard let data = buffers[0].mData else { return }
            buffer.write(interleaved: data.assumingMemoryBound(to: Float.self), frames: frames)
            return
        }

        let channels = min(buffers.count, buffer.channels)
        let needed = frames * buffer.channels
        if scratch.count < needed { scratch = [Float](repeating: 0, count: needed) }
        scratch.withUnsafeMutableBufferPointer { out in
            guard let out = out.baseAddress else { return }
            for channel in 0..<channels {
                guard let data = buffers[channel].mData else { continue }
                let plane = data.assumingMemoryBound(to: Float.self)
                for frame in 0..<frames {
                    out[frame * buffer.channels + channel] = plane[frame]
                }
            }
            buffer.write(interleaved: out, frames: frames)
        }
    }
}

// The callbacks live at file scope on purpose. Declared inside the main-actor
// `attach`, they would inherit its isolation, and CoreMedia calling them from
// the audio thread would trap on the actor check.

private let tapInit: MTAudioProcessingTapInitCallback = { _, clientInfo, storageOut in
    storageOut.pointee = clientInfo
}

private let tapPrepare: MTAudioProcessingTapPrepareCallback = { tap, _, format in
    capture(of: tap).prepare(format: format.pointee)
}

private let tapProcess: MTAudioProcessingTapProcessCallback = {
    tap, frames, _, bufferList, framesOut, flagsOut in
    let status = MTAudioProcessingTapGetSourceAudio(tap, frames, bufferList, flagsOut, nil, framesOut)
    guard status == noErr else { return }
    capture(of: tap).process(bufferList, frames: framesOut.pointee)
}

private func capture(of tap: MTAudioProcessingTap) -> AudioCapture {
    Unmanaged<AudioCapture>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
}
