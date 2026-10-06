import AppKit
import RaTamerCore

CrashReporter.install()

let application = NSApplication.shared
// Aplica a policy ANTES do run(): depois que o Dock registra o app como
// .regular, a volta para .accessory no didFinishLaunching deixa o ícone
// fantasma no Dock (macOS 27). Lê o config direto do disco para não
// depender do AppModel antes do launch.
if let data = try? Data(contentsOf: ConfigStore.defaultFileURL()),
   let config = try? JSONDecoder().decode(Config.self, from: data),
   config.menuBarOnly == true {
    let ok = application.setActivationPolicy(.accessory)
    NSLog("[ActivationPolicy] reason=pre-run menuBarOnly=1 ok=%d", ok ? 1 : 0)
}

let delegate = AppDelegate()
application.delegate = delegate
application.run()
