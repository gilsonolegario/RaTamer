import CoreAudio

/// In-process control of the default output device's volume.
///
/// Replaces the AppleScript `set volume output volume ...` path that used to
/// spawn `/usr/bin/osascript` as a child of RaTamer. On macOS 27 the Dock
/// attributed that child to RaTamer and briefly inserted a tile next to the
/// clock — even though the app is a menu-bar-only UIElement — every time a
/// volume action (or any other `system` action) fired. Doing the HAL work in
/// process removes the child process entirely.
///
/// Devices without volume control (e.g. HDMI displays that report the volume
/// as fixed) report no `kAudioDevicePropertyVolumeScalar`; `apply` then throws
/// `Unavailable` instead of mutating anything.
public enum VolumeStep: Float, Equatable, Sendable {
    /// ±10 on the AppleScript 0–100 scale (0.10 in the scalar 0–1 space).
    case normal = 0.10
    /// ±3 on the AppleScript 0–100 scale.
    case small = 0.03
}

public enum VolumeAdjustment: Equatable, Sendable {
    case increase(VolumeStep)
    case decrease(VolumeStep)
    case mute
}

public protocol VolumeControlling {
    func apply(_ adjustment: VolumeAdjustment) throws
}

public struct VolumeController: VolumeControlling {
    public struct Unavailable: Error, CustomStringConvertible {
        public let message: String
        public var description: String { message }
    }

    public init() {}

    public func apply(_ adjustment: VolumeAdjustment) throws {
        let deviceID = try Self.defaultOutputDevice()
        switch adjustment {
        case .mute:
            guard Self.hasProperty(deviceID: deviceID, selector: kAudioDevicePropertyMute) else {
                throw Unavailable(message: "default output device does not support mute")
            }
            var mute: UInt32 = 1
            try Self.set(deviceID: deviceID, selector: kAudioDevicePropertyMute, value: &mute)
        case .increase(let step), .decrease(let step):
            guard Self.hasProperty(deviceID: deviceID, selector: kAudioDevicePropertyVolumeScalar) else {
                throw Unavailable(message: "default output device does not support volume control")
            }
            var current: Float32 = 0
            var size = UInt32(MemoryLayout<Float32>.size)
            try Self.get(deviceID: deviceID, selector: kAudioDevicePropertyVolumeScalar,
                         value: &current, size: &size)
            let sign: Float = {
                switch adjustment {
                case .increase: return 1
                case .decrease: return -1
                case .mute: return 0
                }
            }()
            var next = Self.clamped(volume: current, plus: sign * step.rawValue)
            try Self.set(deviceID: deviceID, selector: kAudioDevicePropertyVolumeScalar, value: &next)
        }
    }

    /// Pure clamping so tests can cover edge behavior without audio hardware.
    /// The old AppleScript clamped to the 0–100 output range; scalar volume is
    /// 0–1, so the same rule is `min(max(volume + delta, 0), 1)`.
    public static func clamped(volume: Float, plus delta: Float) -> Float {
        min(max(volume + delta, 0), 1)
    }

    // MARK: - CoreAudio HAL

    private static func defaultOutputDevice() throws -> AudioDeviceID {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        try check(AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID))
        guard deviceID != 0 else {
            throw Unavailable(message: "no default output device")
        }
        return deviceID
    }

    private static func propertyAddress(_ selector: AudioObjectPropertySelector)
        -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)
    }

    private static func hasProperty(deviceID: AudioDeviceID,
                                    selector: AudioObjectPropertySelector) -> Bool {
        var address = propertyAddress(selector)
        return AudioObjectHasProperty(deviceID, &address)
    }

    private static func get<T>(deviceID: AudioDeviceID,
                               selector: AudioObjectPropertySelector,
                               value: inout T, size: inout UInt32) throws {
        var address = propertyAddress(selector)
        try check(AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &value))
    }

    private static func set<T>(deviceID: AudioDeviceID,
                               selector: AudioObjectPropertySelector,
                               value: inout T) throws {
        var address = propertyAddress(selector)
        try check(AudioObjectSetPropertyData(
            deviceID, &address, 0, nil, UInt32(MemoryLayout<T>.size), &value))
    }

    private static func check(_ status: OSStatus) throws {
        guard status == noErr else {
            throw Unavailable(message: "CoreAudio error \(status)")
        }
    }
}