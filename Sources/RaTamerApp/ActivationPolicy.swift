import AppKit

/// Centraliza a troca de activationPolicy (.accessory esconde do Dock,
/// .regular mostra). Todo ponto que abre/fecha janela deve reaplicar via
/// este helper, porque no macOS 27 abrir uma janela promove o app a
/// .regular e a volta para .accessory precisa ser explícita.
enum ActivationPolicyHelper {
    static func apply(reason: String) {
        let menuBarOnly = AppModel.shared.configStore.load().menuBarOnly == true
        applyValue(menuBarOnly: menuBarOnly, reason: reason)
    }

    static func applyValue(menuBarOnly: Bool, reason: String) {
        let target: NSApplication.ActivationPolicy = menuBarOnly ? .accessory : .regular
        let current = NSApp.activationPolicy()
        guard current != target else { return }
        let ok = NSApp.setActivationPolicy(target)
        NSLog("[ActivationPolicy] reason=%@ menuBarOnly=%d target=%ld ok=%d now=%ld",
              reason, menuBarOnly ? 1 : 0, target.rawValue, ok ? 1 : 0,
              NSApp.activationPolicy().rawValue)
        CrashReporter.addBreadcrumb("activationPolicy reason=\(reason) ok=\(ok)")
    }
}
