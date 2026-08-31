import Foundation
import MediaPlayer
import SkywaveKit

/// Publishes what is on air to the system: the Now Playing card in Control
/// Centre, and the media keys.
@MainActor
final class NowPlayingCenter {
    var onPlay: (() -> Void)?
    var onPause: (() -> Void)?

    private let info = MPNowPlayingInfoCenter.default()
    private let commands = MPRemoteCommandCenter.shared()

    func start() {
        commands.playCommand.addTarget { [weak self] _ in
            self?.onPlay?()
            return .success
        }
        for command in [commands.pauseCommand, commands.stopCommand] {
            command.addTarget { [weak self] _ in
                self?.onPause?()
                return .success
            }
        }
        commands.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.onPlay?()
            return .success
        }
        // Live radio has nothing to seek or skip through.
        for command in [
            commands.nextTrackCommand, commands.previousTrackCommand,
            commands.changePlaybackPositionCommand, commands.seekForwardCommand,
            commands.seekBackwardCommand,
        ] {
            command.isEnabled = false
        }
    }

    func update(station: Station?, playing: NowPlaying, isPlaying: Bool) {
        guard let station else {
            info.nowPlayingInfo = nil
            info.playbackState = .stopped
            return
        }
        // The track is the most specific thing known, then the show; the station
        // name is the fallback, since several stations report nothing at all.
        let title = playing.track ?? playing.show ?? station.name
        let subtitle = playing.track == nil ? station.city : station.name
        info.nowPlayingInfo = [
            MPMediaItemPropertyTitle: title,
            MPMediaItemPropertyArtist: subtitle,
            MPMediaItemPropertyAlbumTitle: station.name,
            MPNowPlayingInfoPropertyIsLiveStream: true,
        ]
        info.playbackState = isPlaying ? .playing : .paused
    }
}
