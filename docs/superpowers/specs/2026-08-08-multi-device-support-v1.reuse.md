# Relatório de Reuso — Multi-Device Support (device-aware UI)

**Tarefa:** `multi-device-support` (spec `2026-08-08-multi-device-support-design.md`)
**Data:** 2026-08-08
**Escopo da pesquisa:** bibliotecas, SDKs e OSS prontos para: (a) nome do produto via HID++/IOKit, (b) presets de DPI por device, (c) detecção de capacidades (SmartShift, HiResWheel, bateria), (d) UI adaptativa por device.
**Vínculo do projeto:** Swift 6, SwiftPM puro, **sem novas dependências** (sem Cocoapods/Carthage, sem binários). macOS 13+.

---

## Resumo executivo

**Não existe biblioteca Swift pronta para integrar** que cubra a feature sem violar o vínculo "sem novas dependências" e sem trazer risco de manutenção. Os candidatos Swift existentes (`niw/HIDPP`, `meech-io/logi-cli`, `lintuxt/solcito`) são imaturos (0–4 stars, poucos commits, sem releases) ou GPL-2.0 (copyleft, incompatível com o espírito do projeto).

**Recomendação: REUSAR COMO REFERÊNCIA (não como dependência).** O código-fonte do RatTamer já implementa o protocolo HID++ 2.0 necessário (0x2201 DPI list com expansão de range, 0x2121 HiResWheel com flags, 0x1000 bateria, 0x1B04 reprog). A feature é majoritariamente **lógica de apresentação** (nome do device, presets de DPI, esconder opções não suportadas) — e o padrão de referência para isso é o **Mouser** (UI device-aware) + **Solaar** (tabelas de presets por device) + **OpenLogi docs** (wire format exato).

---

## 2. Fatos de protocolo confirmados (base para a implementação)

### 2.1 Nome do produto

- **IOKit (`kIOHIDProductKey`)** — já lido no `IOHIDDeviceWrapper` do RatTamer. Retorna o nome do device HID:
  - **Bluetooth direto:** nome real do mouse (ex.: "MX Master 2S").
  - **Receiver Unifying/Bolt:** retorna **"USB Receiver"** (nome do receiver, não do mouse). O nome real do mouse só vem via HID++.
- **HID++ 2.0 feature `0x0005 DEVICE_NAME`** (getDeviceNameCount fn 0, getDeviceName fn 1, getDeviceType fn 2) — nome de marketing do device, lido em chunks de 16 bytes. Implementado no Solaar (`get_name()` em `hidpp20.py`) e no OpenLogi (`get_whole_device_name()`).
- **Fallback "HID++ device"** (já no spec do RatTamer) cobre o caso receiver.

### 2.2 DPI (feature `0x2201 ADJUSTABLE_DPI`)

- getSensorCount (fn 0), getSensorDpiList (fn 1), getSensorDpi (fn 2), setSensorDpi (fn 3).
- **Encoding de range**: valores 0x0001..0xFFFF; se os 3 bits altos forem `0b111`, é um range com passo nos 13 bits baixos (ex.: `0xE032` = range com step 50). Terminador `0x0000`.
- O código atual do RatTamer (`AdjustableDPI.getSensorDpiList` + `expand()`) já implementa isso.
- **Presets reais por device** (fonte: Solaar `settings_templates.py` + specs Logitech):
  - MX Master (1ª geração): 400–1600, passo 200
  - MX Master 2S: 200–4000, passo 50
  - MX Master 3: 200–4000, passo 50
  - MX Master 3S: 200–8000, passo 50
  - MX Anywhere 3S: 200–8000, passo 50
  - MX Vertical: 400–4000, passo 50

### 2.3 SmartShift / HiResWheel

- **`0x2121 HIRES_WHEEL`**: `getInfo` (fn 0) → multiplier + flags: **bit 3 (0x08) = has_invert**, **bit 2 (0x04) = has_switch**. O RatTamer já implementa (`hasSwitch: (flags >> 2) & 1`).
- **`0x2110 SMART_SHIFT`** (MX Master 2S/3) e **`0x2111 SMART_SHIFT_ENHANCED`** (MX Master 3S/4): o Solaar usa 0x2110 para 2S/3 e 0x2111 para 3S/4S. O RatTamer usa `HiResWheel.getInfo().hasSwitch` — correto.
- Nota: o "SmartShift (auto)" da UI está ligado ao CID `0x00C4` (mode shift button) — o Solaar mostra "Smart Shift: Smart Shift" no REPROG CONTROLS V4 do MX Master 3S.

### 2.4 Bateria

- `0x1000 BATTERY_STATUS` (MX Master 2S/3) vs `0x1004 UNIFIED_BATTERY` (MX Master 3S/4S). O RatTamer usa 0x1000 — ok para 2S/3; para 3S/4S o ideal é tentar 0x1004 primeiro.

### 2.5 Reprogrammable controls

- `0x1B04 REPROG_CONTROLS_V4` (MX Master 2S/3/3S) — já usado pelo RatTamer.

### 2.6 Aviso macOS + Bluetooth

- **OpenLogi issue #27**: no macOS, via Bluetooth direto, o HID++ interface (usage page 0xFF00) pode **não ser exposto** para alguns mouses (ex.: MX Master 3). O Logi Options+ usa DriverKit system extension. Via receiver USB (Unifying/Bolt) o 0xFF00 é exposto. Relevante para documentação/UX do RatTamer (se o usuário conectar via Bluetooth e não aparecer, sugerir receiver).

---

## 4. Candidatos avaliados

### 4.1 Solaar — `pwr-Solaar/Solaar` ⭐ REFERÊNCIA PRINCIPAL

- **URL:** https://github.com/pwr-Solaar/Solaar
- **Descrição:** gerenciador de devices Logitech (Linux, GTK). Implementação de referência do protocolo HID++ 2.0 em Python.
- **Prós:** ~9,1k stars, 2.997 commits, ativo (último commit recente); tabelas de presets DPI por device em `settings_templates.py`; `hidpp20.py` com `get_name()`, `get_hires_wheel()`, `AdjustableDpi`; `hidpp20_constants.py` com `SupportedFeature` (0x0005, 0x2121, 0x2201, 0x1004 etc.); lida com range encoding de DPI.
- **Contras:** Python/Linux (não roda no macOS); GPL-2.0 (copyleft — não pode ser copiado para projeto MIT sem contaminação; usar apenas como referência de comportamento).
- **Manutenção:** ativa.
- **Esforço de integração:** zero (referência). Traduzir padrões para Swift é trabalho de leitura, não de código.
- **Recomendação:** **USAR COMO REFERÊNCIA** — fonte de verdade para presets de DPI e wire format.

### 4.2 OpenLogi — `AprilNEA/OpenLogi` ⭐

- **URL:** https://github.com/AprilNEA/OpenLogi (docs: https://openlogi.org/en/hidpp/features/)
- **Descrição:** driver/ecossistema Logitech em Rust (macOS/Linux/Windows) + **documentação de protocolo HID++** (openlogi.org) + crate `hidpp` (Rust).
- **Prós:** ~8,3k stars, 655 commits, ativo; **docs de wire format por feature** (0x0005, 0x2121, 0x2201, 0x2111, 0x1004) — valida o que o RatTamer já implementa; MIT/Apache-2.0 (permissiva); roda no macOS.
- **Contras:** Rust (não Swift); o crate `hidpp` é para uso em Rust; docs são o ativo mais valioso.
- **Pré-manutenção:** ativa.
- **Esforço de integração:** zero (referência).
- **Recomendação:** **USAR COMO REFERÊNCIA** — docs de wire format + confirmação de flags.

### 4.3 Mouser — `TomBadash/Mouser` ⭐
- **URL:** https://github.com/TomBadash/Mouser
- **Descrição:** gerenciador de mouses Logitech em Python/QML (macOS/Windows/Linux), inspirado no Solaar.
- **Prós:** ~5,1k stars, 279 commits, ativo; **MIT** (permissiva); roda no macOS; UI device-aware (esconde opções não suportadas por device, presets de DPI, SmartShift toggle) — exatamente o padrão de UI que a feature pede.
- **Contras:** Python/QML (não Swift); não é biblioteca (app completo).
- **Pré-manutenção:** ativa.
- **Esforço de integração:** zero (referência de comportamento de UI).
- **Recomendação:** **USAR COMO REFERÊNCIA** — padrão de UI adaptativa por device.

### 4.4 logiops — `PixlOne/logiops`
- **URL:** https://github.com/PixlOne/logiops
- **Descrição:** daemon de configuração Logitech em C++ (Linux).
- **Prós:** 4,3k stars, 351 commits; implementa DPI, SmartShift, hiresscroll.
- **Contras:** GPL-3.0 (copyleft); Linux-only; C++.
- **Recomendação:** **USAR COMO REFERÊNCIA** (protocolo), não como dependência.

### 4.5 libratbag — `libratbag/libratbag`
- **URL:** https://github.com/libratbag/libratbag
- **Descrição:** biblioteca de configuração de mouses (C, Linux), usada pelo Piper.
- **Prós:** 1,1k stars; `hidpp20.c/h` com DPI, HiResWheel, battery.
- **Contras:** GPL-2.0; Linux-only; C.
- **Recomendação:** **USAR COMO REFERÊNCIA** (protocolo).

### 4.6 cvuchener/hidpp
- **URL:** https://github.com/cvuchener/hidpp
- **Descrição:** ferramentas de protocolo HID++ em C++ (Linux).
- **Prós:** 115 stars, 171 commits; útil para debug.
- **Contras:** GPL-3.0; Linux; C++.
- **Recomendação:** **USAR COMO REFERÊNCIA** (protocolo).

### 4.7 niw/HIDPP (Swift) — DESCARTAR como dependência
- **URL:** https://github.com/niw/HIDPP
- **Descrição:** biblioteca Swift para HID++ (macOS).
- **Prós:** Swift; MIT.
- **Contras:** 4 stars, 27 commits, "under development", sem releases, sem CI visível; não cobre 0x2201/0x2121/0x0005 de forma completa.
- **Recomendação:** **DESCARTAR como dependência** (imatura); pode servir de referência de código Swift/IOKit.

### 4.8 meech-io/logi-cli (Swift) — ❌
- **URL:** https://github.com/meech-io/logi-cli
- **Descrição:** CLI Swift para Logitech (macOS).
- **Prós:** Swift; MIT.
- **Contras:** 0 stars, 2 commits, criado recentemente; sem releases; cobertura mínima.
- **Recomendação:** **DESCARTAR** (muito novo, sem tração).

### 4.9 solcito — `lintuxt/solcito` (Swift) — ❌
- **URL:** https://github.com/lintuxt/solcito
- **Descrição:** gerenciador de receiver Unifying/Bolt em Swift (macOS, IOKit), transliterado do Solaar.
- **Prós:** Swift; IOKit; macOS 13+; código HID++ em `Sources/HIDPP/`.
- **Contras:** **GPL-2.0** (copyleft — não pode ser incorporado); 0 stars, 6 commits, sem releases; foco em pairing/battery, não em DPI/SmartShift.
- **Recomendação:** **DESCARTAR como dependência** (GPL + imaturo); referência de código Swift/IOKit.

### 4.10 pcolman/mx-battery — ❌
- **URL:** https://github.com/pcolman/mx-battery
- **Descrição:** CLI de bateria para MX Master (Python, macOS, IOKit).
- **Prós:** mostra leitura de IOKit no macOS (`machid.py`).
- **Contras:** GPL-3.0; 1 star, 13 commits; escopo mínimo.
- **Recomendação:** **DESCARTAR** como dependência; referência menor de IOKit.

### 4.11 jlevere/hidpp (Rust) — ❌
- **URL:** https://github.com/jlevere/hidpp
- **Descrição:** crate Rust HID++ (MIT/Apache-2.0).
- **Prós:** permissiva.
- **Contras:** 2 stars, criado 2026-04, sem tração; Rust (não Swift).
- **Recomendação:** **DESCARTAR** (muito novo, sem tração).

### 4.12 Spec HID++ 2.0 (PDF) — fonte primária
- **URL:** https://lekensteyn.nl/files/logitech/logitech_hidpp_2.0_specification_draft_2012-06-04.pdf
- **Descrição:** spec oficial (draft) do protocolo HID++ 2.0.
- **Recomendação:** **USAR COMO REFERÊNCIA** — fonte primária para wire format.

---

## 5. Recomendação final

**NÃO adicionar dependência.** Implementar a feature no código existente do RatTamer, usando como referência:

1. **Solaar** (`hidpp20.py`, `settings_templates.py`) — presets de DPI por device e wire format.
2. **OpenLogi docs** (openlogi.org) — validação do wire format de 0x2201/0x2121/0x0005/0x1004.
3. **Mouser** — padrão de UI device-aware (esconder opções não suportadas, presets de DPI).

**Justificativa do "do zero":** o protocolo já está implementado no RatTamer (0x2201, 0x2121, 0x1000, 0x1B04, `kIOHIDProductKey`). O que falta é lógica de apresentação (nome do device via 0x0005 para receiver, presets de DPI, capabilities) — não há biblioteca Swift madura que entregue isso sem violar o vínculo de dependências ou a licença. O esforço de implementar é pequeno (2–3 arquivos) e o risco de integrar dependência imatura/GPL é maior que o benefício.

**Ações concretas para o `edit`:**
1. `HIDDevice.productName` — manter leitura de `kIOHIDProductKey`; se for "USB Receiver" (ou fallback), tentar feature `0x0005` (getDeviceNameCount/getDeviceName) antes do fallback "HID++ device".
2. `DeviceCapabilities` — derivar de features presentes (0x2201 → DPI; 0x2121 flags bit 2 → SmartShift; 0x1000/0x1004 → bateria; 0x1B04 → botões).
3. Presets de DPI — usar a lista real do sensor (0x2201 fn 1) e, se indisponível, tabela por device (MX Master 2S: 200–4000/50; 3S: 200–8000/50; etc.).
4. UI — esconder opções não suportadas (padrão Mouser); mostrar nome do device no header.
5. Documentar no README o aviso de Bluetooth no macOS (HID++ pode não ser exposto; usar receiver).