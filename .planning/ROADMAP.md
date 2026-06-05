# Roadmap: TypeFlow

## Milestones

- ✅ **v1.0 MVP** — Phases 1-5 (shipped 2026-05-23)

## Phases

<details>
<summary>✅ v1.0 MVP (Phases 1-5) — SHIPPED 2026-05-23</summary>

- [x] Phase 1: Core Injection & Foundation (1/1 plans) — completed
- [x] Phase 2: Local AI Engine & Basic Completion (1/1 plans) — completed
- [x] Phase 3: Advanced Context Pipeline (1/1 plans) — completed
- [x] Phase 4: Settings & Personalization (1/1 plans) — completed
- [x] Phase 5: Tone, Snippets & App Overrides (1/1 plans) — completed

</details>

## Progress

| Phase                                | Milestone | Plans Complete | Status      | Completed  |
| ------------------------------------ | --------- | -------------- | ----------- | ---------- |
| 1. Core Injection & Foundation       | v1.0      | 1/1            | Complete    | 2026-05-23 |
| 2. Local AI Engine & Basic Completion| v1.0      | 1/1            | Complete    | 2026-05-23 |
| 3. Advanced Context Pipeline         | v1.0      | 1/1            | Complete    | 2026-05-23 |
| 4. Settings & Personalization        | v1.0      | 1/1            | Complete    | 2026-05-23 |
| 5. Tone, Snippets & App Overrides    | v1.0      | 1/1            | Complete    | 2026-05-23 |
| 6. Critical Bug Fixes                | v1.1      | 1/1            | Complete    | 2026-05-23 |
| 7. Model UI & Downloads              | v1.1      | 2/2            | Complete    | 2026-05-23 |
| 10. Continuous Learning & Auto-Correct| v1.2     | 2/2            | Complete    | 2026-06-03 |
| 11. Tone Profiles                    | v1.2      | 1/1            | Complete    | 2026-06-03 |
| 12. Snippet Memory & Shortcodes      | v1.2      | 1/1            | Complete    | 2026-06-03 |

## Phase 6: Critical Bug Fixes
**Goal**: Fix accessibility loops and injection monitor bugs.
**Requirements**: BUGS-01, BUGS-02
**Success Criteria**:
- App launches without prompting for Accessibility if already granted.
- Ghost text injects correctly into standard text fields using CGEvent.

## Phase 7: Model UI & Downloads
**Goal**: Add model management UI for MLX downloads and activation.
**Requirements**: MODELS-01, MODELS-02, MODELS-03
**Success Criteria**:
- Model Management tab exists in Settings.
- User can download Gemma 4 E2B and Qwen 2.5 1.5B with progress indication.
- User can activate a downloaded model.

### Phase 8: Completions Overhaul

**Goal:** [To be planned]
**Requirements**: TBD
**Depends on:** Phase 7
**Plans:** 0 plans

Plans:
- [ ] TBD (run /gsd-plan-phase 8 to break down)

### Phase 9: Completions Overhaul

**Goal:** [To be planned]
**Requirements**: TBD
**Depends on:** Phase 8
**Plans:** 0 plans

Plans:
- [ ] TBD (run /gsd-plan-phase 9 to break down)

### Phase 10: Continuous Learning and Auto-Correct

**Goal:** [To be planned]
**Requirements**: TBD
**Depends on:** Phase 9
**Plans:** 2/2 plans complete

Plans:
- [x] TBD (run /gsd-plan-phase 10 to break down) (completed 2026-06-03)

### Phase 11: Tone Profiles

**Goal:** [To be planned]
**Requirements**: TBD
**Depends on:** Phase 10
**Plans:** 0 plans

Plans:
- [ ] TBD (run /gsd-plan-phase 11 to break down)

### Phase 12: Snippet Memory and Shortcodes ✅ COMPLETE (2026-06-03)

**Goal:** Implement dynamic shortcode variables and automatic snippet learning: dynamic placeholders, prefix requirements, word boundary checks, encrypted storage, and automatic snippet suggestions from typing history.
**Requirements**: SNIP-01, SNIP-02, SNIP-03, SNIP-04
**Depends on:** Phase 11
**Plans:** 1/1 plans complete

Plans:
- [x] 12-PLAN.md (Wave 1: dynamic variables, boundaries, secure storage, and auto-suggestion) (completed 2026-06-03)

### Phase 13: Productivity Dashboard

**Goal:** Add a native macOS productivity dashboard window accessible from the menu bar, showing all-time stats (completions accepted, words saved, acceptance rate), a 30-day bar chart, and snippet/history counters. Backed by a new `UsageStatsManager` that instruments 4 call sites in `CompletionManager` to record usage events locally.
**Requirements**: TBD
**Depends on:** Phase 12
**Plans:** 1/1 plans complete

Plans:
- [x] 13-PLAN.md (Wave 1: UsageStatsManager + instrumentation | Wave 2: DashboardView + menu wiring)

### Phase 14: Rewrite on Selection

**Goal:** [To be planned]
**Requirements**: TBD
**Depends on:** Phase 13
**Plans:** 1/1 plans complete

Plans:
- [x] TBD (run /gsd-plan-phase 14 to break down) (completed 2026-06-03)

### Phase 15: Context-Aware Smart Reply

**Goal:** [To be planned]
**Requirements**: TBD
**Depends on:** Phase 14
**Plans:** 0 plans

Plans:
- [ ] TBD (run /gsd-plan-phase 15 to break down)

### Phase 16: Performance & Battery Emergency

**Goal:** [To be planned]
**Requirements**: TBD
**Depends on:** Phase 15
**Plans:** 2/2 plans complete

Plans:
- [x] TBD (run /gsd-plan-phase 16 to break down) (completed 2026-06-04)

### Phase 17: Context & Zero-Latency Engine

**Goal:** Implement context extraction, app voice map, and MLX KV pre-warming
**Requirements**: TBD
**Depends on:** Phase 16
**Plans:** 1/1 plans complete

Plans:
- [x] 01-PLAN.md (Context extraction, Pre-warming, Tone Map, Spelling toggle)
