# Phase 8: Additional Wearables E2E - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-06-03
**Phase:** 08-additional-wearables-e2e
**Areas discussed:** HR GATT parser (Rust), Upload device_type, Routing BLE no iOS

---

## HR GATT parser (Rust)

| Option | Description | Selected |
|--------|-------------|----------|
| HR + RR intervals | Most useful for HRV analysis; energy/sensor contact ignored | |
| HR apenas | Minimal parser | |
| Todos os campos | HR + RR + energy + sensor contact | ✓ |

**User's choice:** All fields (todos os campos)
**Notes:** Full 0x2A37 coverage.

| Storage Option | Description | Selected |
|----------------|-------------|----------|
| Nova tabela hr_frames | Separate table, clean schema | |
| Tabela existente de frames WHOOP | Reuse with distinct device_type | ✓ |

**User's choice:** Reuse existing frames table
**Notes:** Simpler migration, consistent upload pipeline.

---

## Upload device_type

| Option | Description | Selected |
|--------|-------------|----------|
| "ble_hr_monitor" | Descriptive, unambiguous | |
| "hr_monitor" | Shorter, less specific | |
| Nome do dispositivo BLE | BLE advertised name (e.g. "Polar H10") | ✓ |

**User's choice:** BLE-advertised device name
**Notes:** More granular per brand/model. Planner must handle sanitization (trim, cap at 64 chars, fallback to "unknown_hr_monitor").

---

## Routing BLE no iOS

| Option | Description | Selected |
|--------|-------------|----------|
| Scan unificado com WearableDescriptor | Add 0x180D to whoopServices, use existing scan | |
| Scan separado / modo dedicado | New scan mode for HR monitors | ✓ |

**User's choice:** Scan separado/dedicado
**Notes:** Avoids mixing WHOOP connection state with HR monitor state.

| Connect Option | Description | Selected |
|----------------|-------------|----------|
| Selecção manual apenas | User selects from list | ✓ |
| Auto-connect se único dispositivo HR | Auto-connect if single HR device | |

**User's choice:** Manual selection only
**Notes:** WHOOP already has auto-connect; mixing would create ambiguity.

---

## Claude's Discretion

- WearableDescriptor.genericHRMonitor instance shape
- HR monitor UI (minimal list view)
- Extension file split (GooseBLEClient+HRMonitor.swift vs inline)

## Deferred Ideas

- Auto-connect for HR monitors
- Dedicated HR monitor UI tab
- Apple Watch HR support
- Third wearable type (v3+)
