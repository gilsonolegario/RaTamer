import Foundation

final class EngineEvents {
    static let shared = EngineEvents()
    var onConnected: (() -> Void)?
    var onDisconnected: (() -> Void)?
    private init() {}
}
