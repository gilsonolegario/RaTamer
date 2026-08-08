import Foundation

final class EngineEvents {
    static let shared = EngineEvents()
    var onConnected: (() -> Void)?
    private init() {}
}
