# Pesquisa Técnica — hidd/hidutil e mouses Logitech no macOS (multi-device support)

**Data:** 2026-08-08
**Escopo:** validar/refutar os 5 achados do relatório de reuso (`2026-08-08-multi-device-support-v1.reuse.md`) com fontes primárias, e adicionar profundidade específica do macOS (hidd/hidutil, exposição HID++ receiver vs Bluetooth, matching IOKit, permissões, gotchas de versão).
**Ambiente investigado:** macOS 15.7.8 (Sequoia), arm64, com receiver Unifying Logitech conectado (VID 0x046D, PID 0xC52B).
**Vínculo do projeto:** Swift 6, SwiftPM puro, sem novas dependências, macOS 14+.

---

## Resumo executivo

**Veredito geral: o relatório de reuso está correto na direção, mas com 2 correções importantes e 1 atualização relevante.**

1. **Achado 1 (nome do produto) — CONFIRMADO**, com verificação local: `hidutil list` nesta máquina mostra o receiver Unifying como **"USB Receiver"** (0x046D:0xC52B), e o `ioreg` confirma a interface HID++ (usage page 0xFF00) exposta no registry. O nome real via Bluetooth não pôde ser testado aqui (sem mouse BT conectado), mas é corroborado por fontes (OpenLogi issue #27 mostra o MX Master 3 via BT com os 3 nós HID nomeados pelo mouse).
2. **Achado 2 (presets de DPI) — PARCIALMENTE CONFIRMADO, com correção de fonte.** O Solaar **não** mantém tabela hardcoded de presets por modelo em `settings_templates.py` — ele lê a **lista real do sensor** via 0x2201 fn 1 (`produce_dpi_list`). Os valores citados (200–4000, 200–8000, 400–4000) são corroborados pelas páginas oficiais da Logitech, mas a fonte correta é o device, não o Solaar. O design spec do RatTamer já faz o certo (derivar da lista real, tabela só como fallback).
3. **Achado 3 (SmartShift) — CONFIRMADO**, com **adição crítica**: o `SmartShiftControls` atual do RatTamer só implementa 0x2110 (fn 0/1). Para MX Master 3S/4S o feature é **0x2111 SMART_SHIFT_ENHANCED** com tabela de funções diferente (fn 0 = capabilities, fn 1 = get mode, fn 2 = set mode). A detecção de capacidade via `HiResWheel.getInfo().hasSwitch` (bit 2) está correta.
4. **Achado 4 (bateria) — CONFIRMADO.** 0x1000 é legacy; 0x1004 UNIFIED_BATTERY é o moderno (MX Master 3S usa 0x1004, MX Master 3 usa 0x1000). No macOS não há diferença de transporte — a feature presente é determinada por 0x0001/0x0000. **Correção ao design spec:** `DeviceCapabilities.hasBattery` deve checar 0x1000 **OU** 0x1004.
5. **Achado 5 (Bluetooth) — CONFIRMADO, com atualização importante.** O OpenLogi issue #27 confirma que o macOS **não expõe** a interface HID++ (0xFF00) para MX Master 3 via Bluetooth direto, e que o Logi Options+ resolve com DriverKit system extension. **Novidade:** o OpenLogi v0.3.0+ implementou "BLE-direct HID++ enumeration" que **funciona** para MX Master 3S e MX Master 4 (issue #27 fechado como fixed em v0.5.0), mas **não funciona** para MX Vertical e MX Keys Mini (issue #42, aberto). Ou seja: o workaround existe mas é **device-dependent e experimental** — a via confiável no macOS continua sendo o receiver.

**Achado adicional importante (macOS específico):** `hidutil`/`hidd` **não** remapeiam botões de mouse — apenas teclas (`UserKeyMapping`). Não existe alternativa nativa do macOS para reatribuir botões sem HID++ ou CGEventTap. O RatTamer está no caminho certo ao usar HID++ via IOKit.

---

## Validação dos 5 achados do relatório de reuso

### Achado 1 — Nome do produto: `kIOHIDProductKey` vs feature 0x0005

**Veredito: CONFIRMADO** (com verificação local para o caso receiver).

**Evidência local (macOS 15.7.8, arm64):**
- `hidutil list` mostra o receiver Unifying como `0x46d 0xc52b ... USB Receiver` — ou seja, `kIOHIDProductKey` retorna **"USB Receiver"** para o receiver. (Saída capturada nesta sessão.)
- `ioreg -r -c IOHIDDevice -l` mostra o nó do receiver com `PrimaryUsagePage = 65280` (0xFF00) — a interface HID++ está exposta no registry (é por isso que o `HIDLocator` do RatTamer, que usa `IOServiceMatching("IOHIDDevice")`, a encontra).

**Evidência de fontes:**
- Apple: `kIOHIDProductKey` — "A key that describes the product" (https://developer.apple.com/documentation/iokit/kiohidproductkey). É o nome do **device HID** — no caso do receiver, o device HID é o próprio receiver.
- OpenLogi docs, feature 0x0005 deviceTypeAndName: `getDeviceNameCount()` (fn 0) dá o tamanho, `getDeviceName(offset)` (fn 1) retorna chunks; `getDeviceType` (fn 2) retorna o tipo (Mouse=3, Receiver=7...). (https://openlogi.org/en/hidpp/features/x0005-device-type-and-name)
- Solaar `hidpp20.py` `get_name()` (linhas 1851–1870, verificado no fonte): `feature_request(DEVICE_NAME)` (fn 0) → `name_length`; loop `feature_request(DEVICE_NAME, 0x10, len(name))` (fn 1 com offset) → fragmentos de **16 bytes** (long message), truncados ao tamanho final. (https://github.com/pwr-Solaar/Solaar/blob/master/lib/logitech_receiver/hidpp20.py)
- OpenLogi issue #27: via Bluetooth, o MX Master 3 aparece como 3 nós HID com `PrimaryUsagePage = 0x01` — o nome do produto via BT é o nome do mouse (o macOS usa o nome do device BT). (https://github.com/AprilNEA/OpenLogi/issues/27)

**Detalhe macOS:** o chunk de 16 bytes é o payload da long message HID++ (report ID 0x11, 19 bytes de payload — o Solaar usa `fragment[:name_length - len(name)]` porque o payload da resposta é 16 bytes úteis após o cabeçalho). O RatTamer já tem `buildLong` no `Protocol.swift` — a implementação de 0x0005 é direta.

**Recomendação:** manter `kIOHIDProductKey` como nome primário; se for "USB Receiver" (ou qualquer nome de receiver conhecido), consultar 0x0005 (fn 0 → fn 1 em loop) antes do fallback "HID++ device". O fallback "HID++ device" do design spec está correto para o caso de falha.

---

### Achado 2 — Presets de DPI reais por device

**Veredito: PARCIALMENTE CONFIRMADO — a fonte citada está errada, os valores estão certos.**

**O que o Solaar realmente faz (verificado no código-fonte):**
- `settings_templates.py` → `AdjustableDpi.validator_class.build()` chama `produce_dpi_list(feature, 0x10, 1, device, 0)` — ou seja, **lê a lista real do sensor** via 0x2201 fn 1 (getSensorDpiList). O `choices_universe = NamedInts.range(100, 4000, str, 50)` é apenas um fallback genérico, **não** uma tabela por modelo. (https://github.com/pwr-Solaar/Solaar/blob/master/lib/logitech_receiver/settings_templates.py)
- `produce_dpi_list` confirma o encoding de range que o RatTamer já implementa: `if val >> 13 == 0b111: step = val & 0x1FFF; dpi_list += range(dpi_list[-1] + step, last + 1, step)` — idêntico ao `AdjustableDPI.expand()` do RatTamer.

**Os valores citados no relatório de reuso são corroborados por fontes oficiais:**
- MX Master 3S: "DPI (Minimal and maximal value): 200-8000 dpi" — spec oficial Logitech (https://www.logitech.com/en-us/shop/p/mx-master-3s e https://hub.sync.logitech.com/mx-master-3s).
- MX Vertical: 400–4000 DPI, ajuste em passos de 50 (Logitech/Reddit: https://www.reddit.com/r/logitech/comments/13sjax4/how_to_set_dpi_on_mx_vertical_not_speed/).
- MX Master 2S: 200–4000 (spec Logitech; corroborado por Solaar device dumps).

**Conclusão:** a afirmação "fonte: Solaar settings_templates.py" está **errada como fonte** — o Solaar não mantém tabela por modelo; ele lê do device. A abordagem do design spec do RatTamer (`recommendedPresets(from validList:)` derivando da lista real do sensor, com `DPICycle.defaultPresets` como fallback) é **exatamente** a abordagem do Solaar e está correta. A tabela hardcoded do relatório de reuso pode ser usada apenas como fallback documentado, não como fonte primária.

---

### Achado 3 — SmartShift: 0x2110 vs 0x2111, flag bit 2 do 0x2121

**Veredito: CONFIRMADO, com adição crítica para o RatTamer.**

**Evidência:**
- Solaar `settings_templates.py`: `SmartShift` usa `_F.SMART_SHIFT` (0x2110) com `read_fnid 0x00 / write_fnid 0x10`; `SmartShiftEnhanced` usa `_F.SMART_SHIFT_ENHANCED` (0x2111) com `read_fnid 0x10 / write_fnid 0x20`. (verificado no código)
- Solaar docs (features): `SMART_SHIFT 0x2110` e `SMART_SHIFT_ENHANCED 0x2111` ambos suportados. (https://pwr-solaar.github.io/Solaar/features)
- OpenLogi docs 0x2111 smartShiftEnhanced: fn 0 = get_capabilities (bit 0 = TUNABLE_TORQUE), fn 1 = get_ratchet_control_mode, fn 2 = set_ratchet_control_mode; wire format de 3 bytes. (https://openlogi.org/en/hidpp/features/x2111-smartshift-enhanced)
- OpenLogi docs 0x2121 hiResWheel: `get_wheel_capabilities` → `has_switch = payload[1] & (1 << 2)` (**bit 2 = 0x04**), `has_invert = payload[1] & (1 << 3)` (**bit 3 = 0x08**). (https://openlogi.org/en/hidpp/features/x2121-hires-wheel)

**Adição crítica (não estava no relatório de reuso):** o `SmartShiftControls` atual do RatTamer implementa **apenas 0x2110** (fn 0 = getRatchetControlMode, fn 1 = setRatchetControlMode). Para MX Master 3S/4S, o feature presente é **0x2111** com tabela de funções diferente (fn 0 = capabilities, fn 1 = get mode, fn 2 = set mode) e wire format de 3 bytes. Para a feature multi-device, o RatTamer precisa de uma variante 0x2111 (ou tentar 0x2111 primeiro e cair para 0x2110). A detecção de capacidade via `HiResWheel.getInfo().hasSwitch` (bit 2) está correta e é o jeito certo de decidir se mostra "SmartShift (auto)".

---

### Achado 4 — Bateria: 0x1000 vs 0x1004

**Veredito: CONFIRMADO.**

**Evidência:**
- Linux kernel (patch de Filipe Laíns, autor do Solaar): "0x1004 Unified Battery replaces the old Battery Level Status (0x1000)... MX Anywhere 3 supports the new feature... MX Master 3 supports the Battery Level Status (0x1000)". (https://lkml.iu.edu/2101.1/00463.html)
- Solaar issue #3263: MX Master 3S (via Bolt) usa `UNIFIED_BATTERY {1004}`. (https://github.com/pwr-Solaar/Solaar/issues/3263)
- OpenLogi docs 0x1000: "Devices that advertise 0x1004 will typically not advertise 0x1000; the two serve the same purpose but 0x1004 supersedes it." (https://openlogi.org/en/hidpp/features/x1000-battery-status)

**Detalhe macOS:** não há diferença de transporte — HID++ é agnóstico de transporte (USB/BT/receiver). A feature presente é determinada pela enumeração 0x0001/0x0000. **Recomendação:** tentar 0x1004 primeiro, fallback 0x1000. **Correção ao design spec:** `DeviceCapabilities.hasBattery` deve checar `0x1000 || 0x1004`, não só 0x1000.

---

### Achado 5 — Bluetooth: interface HID++ não exposta no macOS

**Veredito: CONFIRMADO, com atualização importante (workaround parcial existe).**

**Evidência (OpenLogi issue #27, status: confirmed, fechado como fixed):**
- No macOS, via Bluetooth direto, o MX Master 3 aparece como 3 nós HID com `PrimaryUsagePage = 0x01` — **nenhum nó 0xFF00**. `IOHIDManager`/`async-hid` não consegue abrir interface HID++.
- Via receiver USB (Unifying/Bolt), o 0xFF00 **é** exposto e pode ser aberto.
- CoreBluetooth: o serviço GATT vendor `00010000-0000-1000-8000-011F2000046D` (char `00010001-...`) existe mas é **estático** (6 comandos HID++ retornaram os mesmos bytes); o serviço HID-over-GATT `0x1812` **não aparece** — macOS reserva o HID BT para o sistema.
- Logi Options+ resolve com **DriverKit system extension** ("Logi Options+ Driver Installer").
- **Atualização:** o OpenLogi v0.3.0+ implementou "BLE-direct HID++ enumeration" — **confirmado funcionando no MX Master 3S e MX Master 4** (issue #27 fechado em v0.5.0). Porém o **issue #42** (aberto, 2026-06-26) mostra que **MX Vertical e MX Keys Mini via BLE continuam não detectados** no macOS. (https://github.com/AprilNEA/OpenLogi/issues/27, https://github.com/AprilNEA/OpenLogi/issues/42)

**Workaround real para o RatTamer:** não há workaround simples e universal. As opções reais são: (a) receiver USB (Unifying/Bolt) — via confiável; (b) BLE-direct — funciona para alguns modelos (3S/4) mas não para outros (Vertical/MX Keys); (c) DriverKit system extension — fora do escopo (entitlements Apple, notarização). **`hidutil`/`hidd` não conseguem reatribuir botões** (ver seção macOS específica), então não há alternativa nativa.

**Nota sobre o HIDLocator do RatTamer:** o comentário no código ("IOHIDManager never enumerates the Unifying receiver on macOS 15/arm64... kernel registry path is the only reliable source") é consistente com o achado do issue #27 — o macOS não publica o nó 0xFF00 para BT, e o IOHIDManager é pouco confiável para o receiver. O padrão atual (IOServiceMatching + usage pairs 0xFF43/0xFF00/0xFF02) está correto.

---

## Seção macOS específico

### hidd / hidutil — o que o macOS nativo faz

- **`hidutil` remapeia apenas teclas** via `UserKeyMapping` (`HIDKeyboardModifierMappingSrc/Dst`, usage page 0x700000000). Fonte primária: Apple TN2450 "Remapping Keys in macOS 10.12 Sierra" (https://developer.apple.com/library/archive/technotes/tn2450/_index.html).
- **Não remapeia botões de mouse.** Múltiplas fontes: gist drfruct ("Unfortunately I was unable to find a solution to remapping anything other than keys", com análise do IOHIDFamily `IOHIDKeyboardFilter::remapKey`); Apple StackExchange ("you will need to find another way to configure mouse buttons 3-5"). (https://gist.github.com/drfruct/c64ac79f5510c4c2e05afd3f11e718e8, https://apple.stackexchange.com/questions/88897/...)
- **`hidutil report --get/--set`** pode enviar feature/output reports crus (`--type feature/output`) — teoricamente dá para mandar HID++ por linha de comando, mas é impraticável para um app (sem sessão, sem notificações, sem matching por device index). (fonte: help do hidutil no gist acima)
- **Gotcha de versão:** no macOS 14.2 o `hidutil` exigia root para remapear; no macOS 15 não exige mais root, mas exige **Input Monitoring** (TCC) para `hidutil` e o terminal. (https://gist.github.com/paultheman/808be117d447c490a29d6405975d41bd)
- **`hidd`** é o daemon do HID Event System; aplica `UserKeyMapping` e `UserIntentMapping` (kIOHIDUserIntentUsagePageKey) — mas o UserIntent é para mapear botões a "intents" do sistema (back/forward), não para reatribuir a ações arbitrárias. Não é um caminho para a feature do RatTamer.

**Conclusão para o RatTamer:** o caminho nativo (hidutil/hidd) **não** substitui o HID++ para reatribuição de botões. O HID++ via IOKit (já implementado) é a abordagem correta. O `hidutil` pode ser útil apenas para diagnóstico (`hidutil list`).

---

### Exposição HID++ (usage page 0xFF00) no macOS — receiver vs Bluetooth

| Transporte | 0xFF00 exposto? | Evidência |
|---|---|---|
| Receiver Unifying (0x046D:0xC52B/0xC532) | **Sim** | Verificado localmente: `ioreg` mostra `PrimaryUsagePage = 65280` (0xFF00); `hidutil list` mostra "USB Receiver". |
| Receiver Bolt (0x046D:0xC548) | **Sim** | OpenLogi docs: Bolt é detectado por VID/PID e fala HID++ 1.0/2.0 (https://openlogi.org/en/hidpp/receivers). |
| Bluetooth direto (MX Master 3) | **Não** | OpenLogi issue #27: só nós com `PrimaryUsagePage = 0x01`. |
| Bluetooth direto (MX Master 3S/4) | **Parcial** | OpenLogi v0.3.0+ BLE-direct funciona (issue #27 fixed); MX Vertical/MX Keys Mini não (issue #42). |
| USB cabeado | **Sim** | OpenLogi docs: wired devices enumeram como inventory próprio. |

**Matching IOKit no RatTamer:** o `HIDLocator` já usa o padrão correto para macOS:
- `IOServiceMatching("IOHIDDevice")` + `IOHIDDeviceCreate` (registry path) — necessário porque o IOHIDManager não enumera o receiver no macOS 15/arm64 (comentário no código).
- Filtro por `kIOHIDVendorIDKey == 0x046D` + usage pairs contendo 0xFF43/0xFF00/0xFF02.
- Para multi-device: o mesmo padrão encontra o receiver; o device index (0x01..0x06) é resolvido via HID++ 1.0 (receiver) ou direto (BT/USB). O OpenLogi usa `RECEIVER_DEVICE_INDEX = 0xFF` para o receiver e device index por slot para os paired devices.

---

### Permissões e gotchas de macOS 14+

- **Input Monitoring (TCC `kTCCServiceListenEvent`)** é exigido para `IOHIDManagerOpen` — sem ele, `kIOReturnNotPermitted`/`TCC deny`. (https://nachtimwald.com/2020/11/08/macos-iohidmanager-permission-issue, https://bugs.winehq.org/show_bug.cgi?id=50153). O RatTamer já tem onboarding de permissões (`Permissions.swift`).
- **App Sandbox quebra IOKit feature reports silenciosamente** — "IOKit feature reports fail silently with sandbox on". Para distribuição fora da App Store, o app não deve ter App Sandbox (ou deve ter as entitlements `com.apple.security.device.usb` e `com.apple.security.device.bluetooth`). (https://dev.to/paulcontr_/usb-hid-on-macos-talking-to-devices-with-iokit-3g2n, https://developer.apple.com/documentation/security/app-sandbox)
- **macOS 14+ (Sonoma/Sequoia):** sem mudanças estruturais no IOHIDManager para este caso; o gotcha real é o TCC (Input Monitoring) e o comportamento do receiver no registry (já tratado pelo HIDLocator). O OpenLogi (macOS 13+) roda com Input Monitoring concedido — mesmo requisito do RatTamer.
- **Conflito com Logi Options+/G HUB:** "only one app can own a receiver at a time" — o OpenLogi documenta que é preciso sair do Options+ (incluindo o agente de menu bar). O RatTamer deve documentar o mesmo. (https://openlogi.org/en)

---

## Referências OSS para o macOS (qual usar como referência)

| Projeto | Linguagem | Licença | macOS? | Veredito |
|---|---|---|---|---|
| **Solaar** (pwr-Solaar/Solaar) | Python | GPL-2.0 | Não (Linux) | **Referência de protocolo** — `hidpp20.py` (get_name, get_hires_wheel, battery), `settings_templates.py` (produce_dpi_list, SmartShift 0x2110/0x2111). Não copiar código (GPL). |
| **OpenLogi** (AprilNEA/OpenLogi) | Rust | MIT/Apache-2.0 | **Sim** | **Referência mais confiável para macOS** — roda no macOS, docs de wire format por feature (0x0005, 0x2121, 0x2111, 0x2201, 0x1004), e o único com solução BLE-direct (parcial). |
| **Mouser** (TomBadash/Mouser) | Python/QML | MIT | Sim | Referência de UI device-aware (esconde opções não suportadas, presets de DPI). |
| **niw/HIDPP** (Swift) | Swift | MIT | Sim | **Imaturo** (4 stars, 27 commits, sem releases, "under development") — descartar como dependência; referência menor de código Swift/IOKit. |
| **logi-cli** (meech-io) | Swift | MIT | Sim | 0 stars, 2 commits — descartar. |
| **solcito** (lintuxt) | Swift | GPL-2.0 | Sim | GPL + imaturo — descartar como dependência. |
| **logiops** (PixlOne) | C++ | GPL-3.0 | Não | Referência de protocolo (Linux). |
| **Spec HID++ 2.0** (PDF) | — | — | — | Fonte primária do wire format (https://lekensteyn.nl/files/logitech/logitech_hidpp_2.0_specification_draft_2012-06-04.pdf). |

**Recomendação:** usar **OpenLogi docs** como fonte primária de wire format (permissiva, macOS, ativa) + **Solaar** como fonte de comportamento (GPL, só leitura) + **Mouser** como padrão de UI. Nenhuma dependência nova.

---

## Recomendações concretas de implementação (RatTamer)

1. **Nome do produto (0x0005):** no macOS, para receiver (productName == "USB Receiver"), implementar feature 0x0005: fn 0 (getDeviceNameCount) → loop fn 1 (getDeviceName, offset em bytes, chunks de 16) → concatenar e decodificar UTF-8. Usar `buildLong` do `Protocol` (payload 19 bytes; o Solaar usa `fragment[:name_length - len(name)]`). Fallback "HID++ device" se falhar.
2. **Presets de DPI:** manter a abordagem do design spec — derivar da lista real do sensor (`AdjustableDPI.getSensorDpiList(sensor: 0)` + `expand()`), com `DPICycle.defaultPresets` como fallback. **Não** criar tabela hardcoded por modelo (o Solaar não faz isso; a lista real é a fonte de verdade). Se quiser fallback documentado, usar os valores oficiais Logitech (2S: 200–4000/50; 3S: 200–8000/50; Vertical: 400–4000/50).
3. **SmartShift (0x2111):** adicionar variante 0x2111 (fn 0 = capabilities, fn 1 = get_ratchet_control_mode, fn 2 = set_ratchet_control_mode, payload 3 bytes) e tentar 0x2111 antes de 0x2110. Manter `hasSwitch` (bit 2 do 0x2121 getInfo) como detecção de capacidade para a UI.
4. **Bateria (0x1004):** tentar 0x1004 primeiro, fallback 0x1000. Corrigir `DeviceCapabilities.hasBattery` para `0x1000 || 0x1004`.
5. **Bluetooth:** documentar no README/onboarding: via BT direto, o HID++ pode não ser exposto no macOS (MX Master 3, MX Vertical, MX Keys Mini); sugerir receiver Unifying/Bolt. Não investir em BLE-direct agora (device-dependent, experimental no OpenLogi).
6. **Permissões:** garantir Input Monitoring (TCC) no onboarding (já existe); se distribuir sandboxed, adicionar `com.apple.security.device.usb` e `com.apple.security.device.bluetooth`; documentar conflito com Logi Options+ (só um app pode "possuir" o receiver).
7. **Diagnóstico:** usar `hidutil list` e `ioreg -r -c IOHIDDevice` como ferramentas de debug (já usadas no `RatDiagnose`).

---

## Tabela de referências

| Nome | URL | O que confirma |
|---|---|---|
| Apple `kIOHIDProductKey` | https://developer.apple.com/documentation/iokit/kiohidproductkey | Chave de nome do produto HID |
| Apple TN2450 (hidutil) | https://developer.apple.com/library/archive/technotes/tn2450/_index.html | hidutil remapeia teclas (UserKeyMapping); não botões |
| OpenLogi docs 0x0005 | https://openlogi.org/en/hidpp/features/x0005-device-type-and-name | getDeviceNameCount/getDeviceName/getDeviceType |
| OpenLogi docs 0x2121 | https://openlogi.org/en/hidpp/features/x2121-hires-wheel | bit 2 = has_switch, bit 3 = has_invert |
| OpenLogi docs 0x2111 | https://openlogi.org/en/hidpp/features/x2111-smartshift-enhanced | 0x2111 fn 0/1/2, wire format 3 bytes |
| OpenLogi docs 0x1000 | https://openlogi.org/en/hidpp/features/x1000-battery-status | 0x1000 legacy, 0x1004 supersede |
| OpenLogi issue #27 | https://github.com/AprilNEA/OpenLogi/issues/27 | BT não expõe 0xFF00 no macOS; BLE-direct fixed p/ 3S/4 |
| OpenLogi issue #42 | https://github.com/AprilNEA/OpenLogi/issues/42 | BLE-direct NÃO funciona p/ MX Vertical/MX Keys Mini |
| OpenLogi docs receivers | https://openlogi.org/en/hidpp/receivers | VID/PID receivers (C52B, C548), device index 0xFF |
| Solaar `hidpp20.py` | https://github.com/pwr-Solaar/Solaar/blob/master/lib/logitech_receiver/hidpp20.py | get_name (0x0005, chunks 16), get_hires_wheel |
| Solaar `settings_templates.py` | https://github.com/pwr-Solaar/Solaar/blob/master/lib/logitech_receiver/settings_templates.py | produce_dpi_list (range encoding), SmartShift 0x2110/0x2111 |
| Solaar docs features | https://pwr-solaar.github.io/Solaar/features | 0x2110/0x2111/0x2121/0x2201 suportados |
| Solaar issue #3263 | https://github.com/pwr-Solaar/Solaar/issues/3263 | MX Master 3S usa UNIFIED_BATTERY 0x1004 |
| Linux kernel (battery 1004) | https://lkml.iu.edu/2101.1/00463.html | 0x1004 substitui 0x1000; MX Anywhere 3 = 0x1004, MX Master 3 = 0x1000 |
| Logitech MX Master 3S spec | https://www.logitech.com/us/shop/p/mx-master-3s | DPI 200–8000 |
| Logitech MX Vertical DPI | https://www.reddit.com/r/logitech/comments/13sjv4/how_to_set_dpi_on_mx_vertical_not_speed/ | 400–4000, passos de 50 |
| IOHIDManager permission | https://nachtimwald.com/2020/11/08/macos-iohidmanager-permission-issue | Input Monitoring (TCC) exigido para IOHIDManager |
| IOKit + sandbox | https://dev.to/paulv_/usb-hid-on-macos-talking-to-devices-with-iokit-3g2n | Feature reports falham silenciosamente com sandbox |
| hidutil macOS 14/15 | https://gist.github.com/paultheman/8be117d447c490a1d6405975d41bd | macOS 14.2 root; macOS 15 Input Monitoring |
| hidutil não remapeia mouse | https://gist.github.com/drfruct/38ac79f4c2e05afd3f11e718e8 | "unable to find a solution to remapping anything other than keys" |
| niw/HIDPP | https://github.com/niw/HIDPP | Swift HID++ imaturo (4 stars, sem releases) |
| Spec HID++ 2.0 (PDF) | https://lekensteyn.github.io/files/logid/logitech_hidpp_2.0_specification_draft_2012-06-04.pdf | Wire format primário |

---

## Limitações e riscos

- **Sem mouse Bluetooth conectado nesta máquina** — o comportamento de `kIOHIDProductName` via BT e a exposição 0xFF00 via BT não foram testados localmente; baseados em OpenLogi issues (fontes primárias de quem testou em hardware real).
- **BLE-direct do OpenLogi é experimental e device-dependent** — não recomendado como base de implementação para o RatTamer agora.
- **Contradição entre fontes:** a página da Logitech para MX Master 3S mostra "200-4,000 DPI" em um trecho e "200-8000" em outro (spec oficial). O valor 8000 é o correto (spec técnica oficial "DPI (Minimal and maximal value): 200-8000 dpi"). Teste de verificação: ler a lista real do sensor via 0x2201 fn 1 — a fonte de verdade é o device, não a página.
- **Solaar é GPL-2.0** — usar apenas como referência de comportamento, nunca copiar código (o RatTamer é MIT).

**Teste de verificação sugerido (contradição DPI 3S):** com um MX Master 3S conectado, rodar `getSensorDpiList(sensor: 0)` e conferir se o último valor é 8000 (confirmando a spec oficial) — e comparar com o fallback da tabela.