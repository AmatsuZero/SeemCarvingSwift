# Capability Matrix — Caire Alignment

This document freezes the public, user-facing capability contract for
SeamCarvingSwift and classifies each Caire-inspired capability. It is the
baseline for GUI work; the public library API is intentionally **not** changed
in this step.

Classification legend:

- **existing** — already implemented and reachable through public APIs.
- **requires API exposure** — implemented in Core/Apple but needs GUI wiring.
- **requires new implementation** — not yet present; deferred to a later task.

| # | Capability | Owner | Acceptance criterion | Status |
|---|-----------|-------|----------------------|--------|
| 1 | Shrink and enlarge in both dimensions | Core/Apple | Output reaches requested pixel dimensions | existing |
| 2 | Backward and forward energy | Core | Existing parity tests remain green | existing |
| 3 | Protect and remove masks | Core/UI | Painted masks affect seam selection and remain aligned after edits | requires API exposure |
| 4 | Object removal and optional restoration | Core/UI | Removal mask can be applied and original dimension restored | requires API exposure |
| 5 | Face-aware protection | Vision/UI | Vision face regions become editable protection policy with explicit cadence | requires API exposure |
| 6 | Caire-style large resize optimization | Planner/UI | Explicit opt-in pre-scale mode, never implicit in exact mode | requires new implementation |
| 7 | CPU/Accelerate/Metal selection | Apple/UI | Backend and deterministic mode are visible and explainable | requires API exposure |
| 8 | Progress, cancellation, and preview | Core/UI | User can cancel an active resize and retain the source document | requires API exposure |
| 9 | Image import/export | Platform UI | macOS file URLs, iPhone/iPad Photos/files, and PNG/JPEG export work | requires API exposure |
| 10 | Shared Apple experience | App | Same feature model works on macOS, iPhone, and iPad with adaptive layouts | requires API exposure |

## Face protection is a capability choice, not Pigo compatibility

Caire-inspired face protection (`.caireInspired` Vision mode) is a *capability
choice* within the Vision adapter. It is **not** a claim of compatibility with
Pigo or any other detector. The package uses Apple Vision as the detection
backend; `.caireInspired` only mirrors Caire's policy shape (protect face
rectangles, explicit cadence via `.detectOnce` / `.redetectEachPass`).

## API gap analysis before GUI work

The GUI must be able to construct controls for energy mode, dimension order,
masks, and progress. Verification against `Sources/SeamCarvingCore/ResizePlanner.swift`:

- `ResizeOptions` exposes `energyMode: EnergyMode`, `dimensionOrder: DimensionOrder`,
  `masks: MaskPair`, and `progress: (@Sendable (ResizeProgress) -> Void)?`.
- `AppleSeamCarver.resize(_:toPixelSize:options:)` accepts `ResizeOptions` and
  forwards it to the backend.

**Conclusion: no GUI-blocking API gap was found.** All GUI-relevant controls
(energy mode, dimension order, masks, progress callback) are already expressible
through the public `ResizeOptions` + progress field. No new library APIs are
added in this task — the Caire-style pre-scale API is scheduled for Task 2.
