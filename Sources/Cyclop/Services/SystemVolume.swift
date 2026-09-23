import AudioToolbox
import CoreAudio
import Foundation

@MainActor
final class SystemVolume: ObservableObject {
    @Published private(set) var level: Float?

    private var device: AudioDeviceID?
    private var listener: AudioObjectPropertyListenerBlock?

    private static var volumeAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain
    )

    func start() {
        stop()
        guard let device = Self.defaultOutputDevice(), Self.isSettable(device) else {
            level = nil
            return
        }
        self.device = device
        level = Self.read(device)
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated {
                guard let self, let device = self.device else { return }
                self.level = Self.read(device)
            }
        }
        self.listener = listener
        AudioObjectAddPropertyListenerBlock(device, &Self.volumeAddress, .main, listener)
    }

    func stop() {
        if let device, let listener {
            AudioObjectRemovePropertyListenerBlock(device, &Self.volumeAddress, .main, listener)
        }
        device = nil
        listener = nil
    }

    func set(_ value: Float) {
        guard let device else { return }
        var clamped = min(max(value, 0), 1)
        let status = AudioObjectSetPropertyData(
            device, &Self.volumeAddress, 0, nil, UInt32(MemoryLayout<Float32>.size), &clamped
        )
        if status == noErr {
            level = clamped
        } else {
            NSLog("Cyclop: setting output volume failed: \(status)")
        }
    }

    private static func defaultOutputDevice() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var device = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device
        )
        guard status == noErr, device != kAudioObjectUnknown else { return nil }
        return device
    }

    private static func isSettable(_ device: AudioDeviceID) -> Bool {
        guard AudioObjectHasProperty(device, &volumeAddress) else { return false }
        var settable: DarwinBoolean = false
        return AudioObjectIsPropertySettable(device, &volumeAddress, &settable) == noErr && settable.boolValue
    }

    private static func read(_ device: AudioDeviceID) -> Float? {
        var value = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        let status = AudioObjectGetPropertyData(device, &volumeAddress, 0, nil, &size, &value)
        return status == noErr ? value : nil
    }
}
