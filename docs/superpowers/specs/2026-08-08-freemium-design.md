# RatTamer Freemium — modelo de venda + licenciamento

Data: 2026-08-08

## Objetivo

Monetizar o RatTamer com modelo **freemium**: a versão grátis mantém 100% das
features atuais de remap; um conjunto de features "pro" é liberado por uma
**chave de licença comprada no Gumroad** (pay-what-you-want, compra única,
Lifetime). Um único build serve os dois públicos — o upgrade acontece colando a
chave, sem trocar o `.app`.

## Contexto e achados da investigação

- O RatTamer é um app de menu bar para macOS 14+ que substitui o Logitech
  Options+ no MX Master 2S (remap de botões via HID++ 2.0, nativo, sem daemons).
- Distribuição atual: build ad-hoc via `scripts/build-app.sh` + GitHub Releases.
  **Não notarizado** (decisão de notarizar fica para depois; fora deste spec).
- Repo GitHub **privado** (`gilsonolegario/RaTamer`) — sem fonte pública para
  compilar grátis. Isso é pré-requisito para o modelo pago.
- Features existentes (`Config` em `Sources/RatTamerCore/Core/ConfigStore.swift`):
  remap por botão (shortcut, system, runShortcut, click, gesture, cycleDPI,
  disabled), swap L/R, DPI cycle, thumb wheel L/R, SmartShift (modo +
  sensibilidade), gestures, menu bar only, bateria/watchdog.
- Ponto de execução central: `ActionEngine.execute` (`ActionEngine.swift:146`);
  gestures/SmartShift são orquestrados pelo `EngineController`.
- Há spec/plano de **multi-dispositivo** (`docs/superpowers/specs/2026-08-08-multi-device-support-design.md`)
  ainda não implementado; perfis múltiplos entram junto como feature pro.
- Concorrência: Logitech Options+ (grátis, oficial), Mac Mouse Fix (open
  source), BetterMouse (~US$ 6 pago). Nicho pequeno.

## Decisões de design

1. **Split free/pro.**
   - **Grátis:** remap de botões (shortcut, system, click, cycleDPI, disabled),
     thumb wheel L/R, swap L/R, DPI presets, menu bar only. O free é o app de
     hoje, 100% funcional.
   - **Pro:** gestures, SmartShift (modo + sensibilidade), runShortcut (atalhos
     do Apple Shortcuts), perfis múltiplos + multi-dispositivo.
2. **Preço:** pay-what-you-want com mínimo (US$ 3), compra única Lifetime, via
   product Gumroad "RatTamer Pro" com **License Keys habilitado**.
3. **Versão:** a release que introduz o freemium vira **1.0.0**.

### Arquitetura de licença

Componentes novos em `Sources/RatTamerCore/Core/` (testáveis sem UI):

- **`LicenseKeyStore`** — persiste a chave do usuário em UserDefaults (fora do
  `config.json`, que é só config de mouse).
- **`LicenseClient`** — `URLSession` para `POST
  https://api.gumroad.com/v2/licenses/verify` com `{product_permalink,
  license_key}`; retorna `success` + metadados da compra.
- **`LicenseService`** — estado `unlicensed / validating / active /
  offline-expired / invalid`; validação no startup; **cache offline de 30 dias**
  (chave + resultado no UserDefaults); retry com backoff em falha de rede/429;
  sujeito a injeção do `LicenseClient` (mock nos testes).
- **`Entitlement`** — enum `ProFeature { gestures, smartShift, runShortcut,
  profiles }`; `Entitlement.isPro(_:)` consulta o `LicenseService`.

Enforcamento em duas portas:

1. **Write/UI:** ao atribuir uma ação pro sem licença ativa, o controle mostra
   badge 🔒 e um painel "Unlock Pro" com link para o product do Gumroad. Nada é
   gravado no config.
2. **Apply/runtime:** antes do apply no `EngineController`, o `Config` é
   filtrado por `Entitlement` — features pro são removidas se sem licença
   (protege contra editar `config.json` manualmente). Defesa extra: gate de
   `runShortcut` no `ActionEngine.execute`.

### UX (Settings)

- Nova tab **Pro** no `SimpleTabs`: status da licença, campo para colar a chave,
  botão validar, link "Get RatTamer Pro →".
- Badges 🔒/PRO nos controles das 4 features pro (gestures, SmartShift,
  runShortcut, perfis).
- Popover e onboarding inalterados.

### Distribuição

- Um único build (single-bundle); upgrade = colar a chave no Settings → Pro.
- Gumroad: product "RatTamer Pro", License Keys + PWYW; buyer recebe chave no
  email/download page.
- README: seção de pricing com link para o product e instrução de ativação.
- Notarização: **fora de escopo**, decidida depois (o xattr warning atual
  continua sendo o fluxo de instalação documentado).

### Testes

- `LicenseService` com `LicenseClient` mock: parse OK, chave inválida,
  429/timeout → usa cache offline, expiração do cache de 30 dias.
- `Entitlement`: config com features pro sem licença é filtrado no apply; com
  licença passa intacto; roundtrip de config preserva as features.

## Fora de escopo

- DRM forte, assinaturas, cloud/contas.
- Revogação online: o dashboard do Gumroad já revoga chaves — o `LicenseService`
  só reflete isso na próxima validação.
- Notarização (decisão posterior).
- Perfis múltiplos + multi-dispositivo: a *feature de produto* entra no pro,
  mas a *implementação* é um spec/plano separado (multi-device support).

## Riscos

- **PWYW + chave facilmente compartilhável** → receita dependente da honestidade
  do nicho; aceito dado o mercado pequeno (conversão de PWYW > preço fixo em
  nicho).
- **Nenhuma feature pro nova até 1.0.0** → o "pro" só fica mais atrativo depois
  de lançar perfis/multi-dispositivo; mitigar comunicando roadmap na tab Pro.
- **Cache offline de 30 dias** → janela de uso pós-revogação; aceito, Gumroad
  revoga no dashboard e o impacto prático é baixo.
