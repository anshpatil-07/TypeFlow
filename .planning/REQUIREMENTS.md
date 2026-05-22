# Requirements

## Milestone v1.1 Requirements

### Bug Fixes (BUGS)
- [ ] **BUGS-01**: Fix Accessibility permission loop by checking `AXIsProcessTrusted` without prompt on launch, and providing a manual prompt mechanism.
- [ ] **BUGS-02**: Fix ghost text injection and CGEvent monitor to ensure it accurately detects key events and renders in target apps.

### Model Management (MODELS)
- [ ] **MODELS-01**: Implement Model Management UI tab in Settings displaying available models.
- [ ] **MODELS-02**: Add download functionality with progress indicators for MLX models (Gemma 4 E2B, Qwen 2.5 1.5B).
- [ ] **MODELS-03**: Add an "Activate" toggle to switch between downloaded models for local inference.

## Future Requirements
- Usage statistics and analytics dashboard
- Paragraph completion and alternatives cycler
- Syncing custom instructions via iCloud

## Out of Scope
- Cloud-based LLM APIs — Must be entirely on-device to ensure privacy and meet 150ms latency target
- Non-Apple Silicon Macs — Requires MLX and Neural Engine for on-device performance (macOS 14+ Apple Silicon only)

## Traceability
*(To be populated by roadmap)*
