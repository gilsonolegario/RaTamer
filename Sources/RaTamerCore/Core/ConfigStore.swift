import Foundation

public struct GestureConfig: Codable, Equatable, Hashable {
    public var click: ButtonAction
    public var up: ButtonAction
    public var down: ButtonAction
    public var left: ButtonAction
    public var right: ButtonAction

    private enum CodingKeys: String, CodingKey {
        case click, up, down, left, right
    }

    public init(click: ButtonAction, up: ButtonAction, down: ButtonAction,
                left: ButtonAction, right: ButtonAction) {
        self.click = click
        self.up = up
        self.down = down
        self.left = left
        self.right = right
    }

    public static func logitechDefault() -> GestureConfig {
        return GestureConfig(
            click: .system("missionControl"),
            up: .system("missionControl"),
            down: .system("showDesktop"),
            left: .system("previousSpace"),
            right: .system("nextSpace")
        )
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        click = try Self.decodeAction(from: c, forKey: .click)
        up = try Self.decodeAction(from: c, forKey: .up)
        down = try Self.decodeAction(from: c, forKey: .down)
        left = try Self.decodeAction(from: c, forKey: .left)
        right = try Self.decodeAction(from: c, forKey: .right)
    }

    private static func decodeAction(from c: KeyedDecodingContainer<CodingKeys>,
                                     forKey key: CodingKeys) throws -> ButtonAction {
        if let legacy = try? c.decodeIfPresent(String.self, forKey: key) {
            return .system(legacy)
        }
        return try c.decode(ButtonAction.self, forKey: key)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(click, forKey: .click)
        try c.encode(up, forKey: .up)
        try c.encode(down, forKey: .down)
        try c.encode(left, forKey: .left)
        try c.encode(right, forKey: .right)
    }
}

public indirect enum ButtonAction: Codable, Equatable, Hashable {
    case shortcut(key: String, modifiers: [String])
    case system(String)
    case runShortcut(String)
    case click(button: UInt8)
    case gesture(GestureConfig)
    case cycleDPI
    case disabled

    private enum CodingKeys: String, CodingKey {
        case action, key, modifiers, system, shortcut, button, gesture
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try c.decode(String.self, forKey: .action)
        switch kind {
        case "shortcut":
            self = .shortcut(key: try c.decode(String.self, forKey: .key),
                             modifiers: try c.decode([String].self, forKey: .modifiers))
        case "system":
            self = .system(try c.decode(String.self, forKey: .system))
        case "runShortcut":
            self = .runShortcut(try c.decode(String.self, forKey: .shortcut))
        case "click":
            self = .click(button: try c.decode(UInt8.self, forKey: .button))
        case "gesture":
            self = .gesture(try c.decode(GestureConfig.self, forKey: .gesture))
        case "cycleDPI":
            self = .cycleDPI
        default:
            self = .disabled
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .shortcut(let key, let modifiers):
            try c.encode("shortcut", forKey: .action)
            try c.encode(key, forKey: .key)
            try c.encode(modifiers, forKey: .modifiers)
        case .system(let name):
            try c.encode("system", forKey: .action)
            try c.encode(name, forKey: .system)
        case .runShortcut(let name):
            try c.encode("runShortcut", forKey: .action)
            try c.encode(name, forKey: .shortcut)
        case .click(let button):
            try c.encode("click", forKey: .action)
            try c.encode(button, forKey: .button)
        case .gesture(let config):
            try c.encode("gesture", forKey: .action)
            try c.encode(config, forKey: .gesture)
        case .cycleDPI:
            try c.encode("cycleDPI", forKey: .action)
        case .disabled:
            try c.encode("disabled", forKey: .action)
        }
    }
}

public extension ButtonAction {
    var requiresDivert: Bool {
        self != .disabled
    }
}

public enum ThumbWheelSide: String, Codable, Equatable, Identifiable {
    case left
    case right

    public var id: String { rawValue }
}

public enum SmartShiftMode: String, Codable, Equatable {
    case freespin
    case ratcheted
    case smartshift
}

public extension SmartShiftMode {
    var wheelMode: UInt8 {
        switch self {
        case .freespin: return 1
        case .ratcheted, .smartshift: return 2
        }
    }

    var autoDisengage: UInt8 {
        switch self {
        case .freespin, .smartshift: return 0x00
        case .ratcheted: return 0xFF
        }
    }
}

public struct Config: Codable, Equatable {
    public var version: Int
    public var deviceIndex: UInt8?
    public var buttons: [String: ButtonAction]
    public var dpiFeatureIndex: UInt8?
    public var dpiDeviceIndex: UInt8?
    public var dpiDownValue: UInt8?
    public var dpiAction: ButtonAction?
    public var swapLeftRight: Bool
    public var smartShiftMode: SmartShiftMode?
    public var smartShiftSensitivity: Int?
    public var dpiValue: UInt16?
    public var dpiCycleValues: [UInt16]?
    public var invertScrollDirection: Bool?
    public var smoothScrollEnabled: Bool?
    public var smoothScrollLevel: Double?
    public var smoothScrollAdvanced: ScrollSmoother.Parameters?
    public var menuBarOnly: Bool?
    public var protectTerminals: Bool?
    public var thumbWheelLeft: ButtonAction?
    public var thumbWheelRight: ButtonAction?

    private enum CodingKeys: String, CodingKey {
        case version, deviceIndex, buttons, dpiFeatureIndex, dpiDeviceIndex,
             dpiDownValue, dpiAction, swapLeftRight, smartShiftMode, dpiValue,
             invertScrollDirection, thumbWheelLeft, thumbWheelRight,
             smartShiftSensitivity, dpiCycleValues, menuBarOnly,
             smoothScrollEnabled, smoothScrollLevel, smoothScrollAdvanced,
             protectTerminals
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decode(Int.self, forKey: .version)
        deviceIndex = try c.decodeIfPresent(UInt8.self, forKey: .deviceIndex)
        buttons = try c.decodeIfPresent([String: ButtonAction].self, forKey: .buttons) ?? [:]
        dpiFeatureIndex = try c.decodeIfPresent(UInt8.self, forKey: .dpiFeatureIndex)
        dpiDeviceIndex = try c.decodeIfPresent(UInt8.self, forKey: .dpiDeviceIndex)
        dpiDownValue = try c.decodeIfPresent(UInt8.self, forKey: .dpiDownValue)
        dpiAction = try c.decodeIfPresent(ButtonAction.self, forKey: .dpiAction)
        swapLeftRight = try c.decodeIfPresent(Bool.self, forKey: .swapLeftRight) ?? false
        smartShiftMode = try c.decodeIfPresent(SmartShiftMode.self, forKey: .smartShiftMode)
        smartShiftSensitivity = try c.decodeIfPresent(Int.self, forKey: .smartShiftSensitivity)
        dpiValue = try c.decodeIfPresent(UInt16.self, forKey: .dpiValue)
        dpiCycleValues = try c.decodeIfPresent([UInt16].self, forKey: .dpiCycleValues)
        invertScrollDirection = try c.decodeIfPresent(Bool.self, forKey: .invertScrollDirection)
        smoothScrollEnabled = try c.decodeIfPresent(Bool.self, forKey: .smoothScrollEnabled)
        smoothScrollLevel = try c.decodeIfPresent(Double.self, forKey: .smoothScrollLevel)
        smoothScrollAdvanced = try c.decodeIfPresent(ScrollSmoother.Parameters.self, forKey: .smoothScrollAdvanced)
        menuBarOnly = try c.decodeIfPresent(Bool.self, forKey: .menuBarOnly)
        protectTerminals = try c.decodeIfPresent(Bool.self, forKey: .protectTerminals)
        thumbWheelLeft = try c.decodeIfPresent(ButtonAction.self, forKey: .thumbWheelLeft)
        thumbWheelRight = try c.decodeIfPresent(ButtonAction.self, forKey: .thumbWheelRight)
    }

    public init(version: Int,
                deviceIndex: UInt8?,
                buttons: [String: ButtonAction],
                dpiFeatureIndex: UInt8? = nil,
                dpiDeviceIndex: UInt8? = nil,
                dpiDownValue: UInt8? = nil,
                dpiAction: ButtonAction? = nil,
                 swapLeftRight: Bool = false,
                 smartShiftMode: SmartShiftMode? = nil,
                 smartShiftSensitivity: Int? = nil,
                 dpiValue: UInt16? = nil,
                 dpiCycleValues: [UInt16]? = nil,
                 thumbWheelLeft: ButtonAction? = nil,
                 thumbWheelRight: ButtonAction? = nil) {
        self.version = version
        self.deviceIndex = deviceIndex
        self.buttons = buttons
        self.dpiFeatureIndex = dpiFeatureIndex
        self.dpiDeviceIndex = dpiDeviceIndex
        self.dpiDownValue = dpiDownValue
        self.dpiAction = dpiAction
        self.swapLeftRight = swapLeftRight
        self.smartShiftMode = smartShiftMode
        self.smartShiftSensitivity = smartShiftSensitivity
        self.dpiValue = dpiValue
        self.dpiCycleValues = dpiCycleValues
        self.invertScrollDirection = nil
        self.menuBarOnly = nil
        self.smoothScrollEnabled = nil
        self.smoothScrollLevel = nil
        self.smoothScrollAdvanced = nil
        self.protectTerminals = nil
        self.thumbWheelLeft = thumbWheelLeft
        self.thumbWheelRight = thumbWheelRight
    }

    public static func empty() -> Config {
        return Config(version: 1, deviceIndex: nil, buttons: [:])
    }

    /// First-run defaults (Logitech-like): Back/Forward navigate (macOS
    /// native buttons do nothing without Logitech Options) and the thumb
    /// wheel drives volume, matching migrateLegacy. Only used when no
    /// config file exists yet — existing installs are untouched.
    public static func freshDefaults() -> Config {
        var config = Config(version: 2, deviceIndex: nil, buttons: [
            String(format: "0x%04X", ControlCID.back):
                .shortcut(key: "[", modifiers: ["command"]),
            String(format: "0x%04X", ControlCID.forward):
                .shortcut(key: "]", modifiers: ["command"]),
        ])
        config.thumbWheelLeft = .system("volumeDownSmall")
        config.thumbWheelRight = .system("volumeUpSmall")
        return config
    }

    public func cidKey(_ cid: UInt16) -> String {
        String(format: "0x%04X", cid)
    }

    public func action(forCID cid: UInt16) -> ButtonAction? {
        buttons[cidKey(cid)]
    }

    public mutating func setAction(_ action: ButtonAction, forCID cid: UInt16) {
        buttons[cidKey(cid)] = action
    }

    public func thumbWheelAction(for side: ThumbWheelSide) -> ButtonAction? {
        side == .left ? thumbWheelLeft : thumbWheelRight
    }

    public mutating func setThumbWheelAction(_ action: ButtonAction?, for side: ThumbWheelSide) {
        if side == .left {
            thumbWheelLeft = action
        } else {
            thumbWheelRight = action
        }
    }

    public mutating func migrateLegacy() -> Bool {
        var changed = false
        let isLegacy = version < 2
        if let dpiAction, buttons[cidKey(ControlCID.dpiButton)] == nil {
            buttons[cidKey(ControlCID.dpiButton)] = dpiAction
            self.dpiAction = nil
            changed = true
        } else if isLegacy, dpiFeatureIndex != nil, buttons[cidKey(ControlCID.dpiButton)] == nil {
            buttons[cidKey(ControlCID.dpiButton)] = .shortcut(key: "w", modifiers: ["command"])
            changed = true
        }
        if isLegacy, thumbWheelLeft == nil && thumbWheelRight == nil {
            thumbWheelLeft = .system("volumeDownSmall")
            thumbWheelRight = .system("volumeUpSmall")
            changed = true
        }
        if changed {
            version = 2
        }
        return changed
    }
}

public enum ConfigStoreError: Error {
    case invalidData
}

public final class ConfigStore {
    private let fileURL: URL
    private let lock = NSLock()
    private var cached: Config?
    private var cachedMtime: Date?

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public static func defaultFileURL() -> URL {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        )[0].appendingPathComponent("RatTamer", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("config.json")
    }

    public func load() -> Config {
        let mtime = fileModificationDate()
        if let cached = cachedValue(matching: mtime) {
            return cached
        }
        guard let data = try? Data(contentsOf: fileURL) else {
            let fresh = Config.freshDefaults()
            try? save(fresh)
            store(cached: fresh, mtime: fileModificationDate())
            return fresh
        }
        guard let decoded = try? JSONDecoder().decode(Config.self, from: data) else {
            // Corrupted file: back it up with a unique name so repeated
            // corruptions don't overwrite the previous backup.
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let stamp = formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")
            let backupURL = fileURL.appendingPathExtension("corrupt.\(stamp)")
            try? FileManager.default.moveItem(at: fileURL, to: backupURL)
            let plainCorrupt = fileURL.appendingPathExtension("corrupt")
            if !FileManager.default.fileExists(atPath: plainCorrupt.path) {
                try? FileManager.default.copyItem(at: backupURL, to: plainCorrupt)
            }
            let empty = Config.empty()
            store(cached: empty, mtime: nil)
            return empty
        }
        var config = decoded
        if config.migrateLegacy() {
            try? save(config)
        } else {
            store(cached: config, mtime: mtime)
        }
        return config
    }

    public func loadStrict() throws -> Config {
        guard let data = try? Data(contentsOf: fileURL) else {
            return Config.empty()
        }
        return try JSONDecoder().decode(Config.self, from: data)
    }

    public func save(_ config: Config) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)
        try data.write(to: fileURL, options: .atomic)
        store(cached: config, mtime: fileModificationDate())
    }


    private func fileModificationDate() -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: fileURL.path))?[.modificationDate] as? Date
    }

    private func cachedValue(matching mtime: Date?) -> Config? {
        lock.lock()
        defer { lock.unlock() }
        guard let cached, cachedMtime == mtime else { return nil }
        return cached
    }

    private func store(cached config: Config, mtime: Date?) {
        lock.lock()
        cached = config
        cachedMtime = mtime
        lock.unlock()
    }
}
