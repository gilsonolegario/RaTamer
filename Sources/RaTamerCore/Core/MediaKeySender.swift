import AppKit
import Foundation

/// The system volume keys, the same events a keyboard's volume keys produce.
///
/// Used as a fallback when the default output device has no volume property of
/// its own: HDMI displays report their volume as fixed, so the HAL write in
/// `VolumeController` throws `Unavailable`. Posting the media key hands the
/// intent to whoever owns software volume for that device — an audio utility
/// applying gain in a Core Audio process tap, or macOS itself — so the thumb
/// wheel keeps working on HDMI without a virtual output device in between.
public enum MediaKey: Int32, Equatable, Sendable {
    case volumeUp = 0    // NX_KEYTYPE_SOUND_UP
    case volumeDown = 1  // NX_KEYTYPE_SOUND_DOWN
    case mute = 7        // NX_KEYTYPE_MUTE

    /// Volume steps collapse to a single key: the receiver decides the step
    /// size, so `.increase(.small)` and `.increase(.normal)` both send the
    /// volume-up key.
    public init(_ adjustment: VolumeAdjustment) {
        switch adjustment {
        case .increase: self = .volumeUp
        case .decrease: self = .volumeDown
        case .mute: self = .mute
        }
    }
}

public protocol MediaKeyPosting {
    func post(_ key: MediaKey)
}

public struct SystemMediaKeySender: MediaKeyPosting {
    public init() {}

    public func post(_ key: MediaKey) {
        // System-defined key events: data1 packs the key code and the key-down
        // flag exactly the way the hardware keyboard encodes them. Posting at
        // the HID tap makes them travel the path a real volume key would.
        for isDown in [true, false] {
            let data1 = Int((key.rawValue << 16) | ((isDown ? 0xA : 0xB) << 8))
            guard let event = NSEvent.otherEvent(
                with: .systemDefined,
                location: .zero,
                modifierFlags: NSEvent.ModifierFlags(rawValue: 0xA00),
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                subtype: 8,
                data1: data1,
                data2: -1
            ) else { continue }
            event.cgEvent?.post(tap: .cghidEventTap)
        }
    }
}
