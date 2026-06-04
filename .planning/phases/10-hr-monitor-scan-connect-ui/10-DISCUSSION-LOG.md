# Phase 10: HR Monitor Scan/Connect UI - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-06-04
**Phase:** 10-hr-monitor-scan-connect-ui
**Areas discussed:** Localização do ecrã, Ciclo de vida do scan, Feedback de ligação, Estado do HR monitor

---

## Localização do ecrã

| Option | Description | Selected |
|--------|-------------|----------|
| Nova rota dedicada em More | Nova entrada MoreRoute (.hrMonitor) → ecrã 'HR Monitor' acessível em More > HR Monitor | |
| Segundo panel no DeviceView | Adicionar tab/panel 'HR' ao DeviceView existente | |
| More tab + passo no onboarding | HRMonitorScanView reutilizável: More > HR Monitor + integrado no onboarding como passo de seleção | |
| Só More tab nesta fase | Ecrã acessível em More > HR Monitor. Onboarding não é tocado | ✓ |
| Só onboarding nesta fase | Adicionar passo 'Ligar HR Monitor' ao onboarding | |
| Lista simples | NavigationStack normal com List — scan status, lista de descobertos | |
| Estilo DeviceView | Header visual com nome do dispositivo, painel de status | ✓ |

**User's choice (placement):** Só More tab nesta fase — nova MoreRoute `.hrMonitor`
**User's choice (style):** Estilo DeviceView — visual idêntico ao DeviceView do WHOOP
**Notes:** O utilizador questionou se seria possível integrar no onboarding ou criar uma experiência standalone de HR monitor. Explorámos as opções e concluiu-se que a fase 10 deve construir `HRMonitorView` como ecrã independente em More tab, ficando a integração no onboarding para uma fase futura quando o HR monitor UX estiver estável.

---

## Ciclo de vida do scan

| Option | Description | Selected |
|--------|-------------|----------|
| Automático ao abrir o ecrã | Scan começa em onAppear, para em onDisappear | ✓ |
| Manual via botão Scan | O utilizador toca 'Scan' para começar e 'Stop' para parar | |
| Parar scan quando ligado | Se hrConnectionState == 'connected', não iniciar scan | ✓ |
| Scan mesmo assim | Scan corre sempre, mesmo com dispositivo já ligado | |

**User's choice:** Scan automático no appear; parar quando já ligado
**Notes:** Zero cliques para ver dispositivos disponíveis. Eficiente em termos de bateria e BLE radio quando já existe uma ligação.

---

## Feedback de ligação

| Option | Description | Selected |
|--------|-------------|----------|
| Estado inline na lista | Item tocado muda de aspeto imediatamente (spinner, texto 'A ligar...') | |
| Sheet de confirmação | Sheet surge com nome do dispositivo + botão 'Ligar' | ✓ |
| Alert de confirmação | Alert system com 'Ligar' e 'Cancelar' | |
| ProgressView inline (pós-confirmação) | Spinner inline no item da lista enquanto ligação em curso | ✓ |
| Spinner fullscreen | ZStack com overlay semitransparente durante a ligação | |

**User's choice:** Sheet de confirmação → ProgressView inline após confirmar
**Notes:** O utilizador prefere que haja uma confirmação explícita antes de iniciar a ligação BLE. Após confirmar na sheet, o progresso é mostrado inline no item da lista (não bloqueante).

---

## Estado do HR monitor

| Option | Description | Selected |
|--------|-------------|----------|
| Ecrã de dispositivo ligado (estilo DeviceView) | Header com nome do dispositivo, HR ao vivo, botão de desligar | ✓ |
| Lista de scan com estado 'Ligado' no topo | Dispositivo ligado no topo da lista, scan permanece visível | |
| Ver HR ao vivo (BPM) | HR em tempo real do liveHeartRateBPM | ✓ |
| Desligar (Disconnect) | Botão para desligar e voltar ao scan | ✓ |
| Estado de reconnect | Mostrar hrReconnectState se dispositivo perder ligação | ✓ |

**User's choice:** Ecrã estilo DeviceView com HR ao vivo, disconnect e estado de reconnect
**Notes:** Todos os três elementos de estado foram selecionados. A experiência deve ser visualmente consistente com o WHOOP DeviceView.

---

## Claude's Discretion

- **State propagation:** Como surfaçar `discoveredHRDevices` (plain var em GooseBLEHRMonitorManager) para SwiftUI — Claude decide se adiciona `@Published` em GooseBLEClient ou torna GooseBLEHRMonitorManager ObservableObject. Padrão (a) — promoted state em GooseBLEClient — recomendado por consistência.
- **HR monitor disconnect:** Implementação técnica de cancelar CBPeripheral connection e limpar estado.
- **`@Published var isHRMonitorConnected`:** Convenience property de conveniência, se simplificar a view logic.

## Deferred Ideas

- Integração do ecrã de scan HR monitor no fluxo de onboarding (levantado pelo utilizador — boa ideia futura, mas alarga o scope da fase 10)
- "Remembered HR monitor" com auto-reconnect ao abrir a app — avaliar na fase 11 (HR monitor independent capture)
