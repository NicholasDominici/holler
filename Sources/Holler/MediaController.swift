import CoreAudio
import Foundation

/// Sends a system-wide media pause via the private MediaRemote framework —
/// the explicit pause command (not the toggle), so it's safe when nothing is
/// playing. MediaRemote's now-playing *query* is gated for normal apps on
/// modern macOS, so "is something playing" comes from CoreAudio: whether the
/// default output device is rendering audio for anyone.
final class MediaController {
    static let shared = MediaController()

    private typealias SendCommandFn = @convention(c) (Int32, AnyObject?) -> Bool
    private static let kMRPause: Int32 = 1

    private let sendCommand: SendCommandFn?

    private init() {
        sendCommand = dlopen(
            "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW
        ).flatMap { handle in
            dlsym(handle, "MRMediaRemoteSendCommand")
                .map { unsafeBitCast($0, to: SendCommandFn.self) }
        }
    }

    /// Whether anything is rendering to the default output right now. Sample
    /// this BEFORE playing the ping sound — our own ding counts as audio.
    var outputAudible: Bool { Self.outputDeviceRunning() }

    func pause(wasAudible: Bool) {
        guard wasAudible, let sendCommand else { return }
        _ = sendCommand(Self.kMRPause, nil)
    }

    private static func outputDeviceRunning() -> Bool {
        var deviceID = AudioObjectID(0)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID
        ) == noErr, deviceID != kAudioObjectUnknown else { return false }

        var running: UInt32 = 0
        size = UInt32(MemoryLayout<UInt32>.size)
        address.mSelector = kAudioDevicePropertyDeviceIsRunningSomewhere
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &running) == noErr
        else { return false }
        return running != 0
    }
}
