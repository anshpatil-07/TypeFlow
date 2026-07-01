# TypeFlow Log Auditor

Use this skill when analyzing TypeFlow logs locally for Antigravity or Codex work. The goal is to produce a Codex-style handoff report from local logs without loading or pasting massive logs into chat.

## Rules

- Do not paste full raw logs into chat.
- Run the audit script first. Default mode emits a full structured handoff report:

```bash
python .agents/skills/typeflow-log-auditor/scripts/audit_typeflow_log.py <log-file>
```

- Use compact mode only for quick checks:

```bash
python .agents/skills/typeflow-log-auditor/scripts/audit_typeflow_log.py --compact <log-file>
```

- Base the report on the script output, then add only the smallest amount of context needed.
- Prefer tables and metrics over long prose.
- Keep reports structured, compact, and complete enough for another agent to continue without reading the original log.
- Include enough detail for another agent to continue without rereading the full log.
- Representative examples may include raw log lines, but cap them at 10 raw lines total.
- Do not enforce a strict 12-bullet limit for log-audit reports. They may be longer when needed, provided they stay structured and compact.

## Required Report Shape

Every full log-audit response should include:

1. Log metadata: file, line count, detected stage, confidence, top markers, ambiguity note.
2. Validation/build signals: `swift test_overlap.swift`, `swift test_mem.swift`, `xcodebuild`, and no-code-change/instrumentation-only mentions if present.
3. Stage-specific metrics:
   - Stage 1 ownership/cancellation counters and proof lines.
   - Stage 2 latency, debounce, AX, and model readiness counters.
   - Stage 3 render scheduling, geometry, resolver, and overlay churn counters.
   - Stage 4 quality counts, source breakdowns, and continuation-specific defects.
4. Regression signals: input hijack, overlay layering, geometry failures, model readiness queueing, stale blocks/discards.
5. Representative examples: parsed quality examples and up to 10 total raw lines.
6. Diagnosis: short heuristic explanation of the likely bottleneck or quality root cause.
7. Recommended next step: the smallest safe follow-up.
8. Missing metrics: signals not present in the log.

## Auditor Script

The script parses TypeFlow logs and emits markdown metrics for latency, debounce, render scheduling, geometry, Stage 1A/1B, quality-audit, overlay, input hijack, and model-readiness signals.

Stage detection precedence:

1. `[QualityAudit]` => Stage 4
2. `[RenderSchedule]`, `[RenderPipeline]`, `[GeometryProbe]`, `[EditableResolver]` => Stage 3
3. `[DebounceAudit]`, `[LatencySummary]`, `[AXHotPath]`, `[ModelReadiness]` => Stage 2
4. `[Stage1B]` / Stage1A safety logs => Stage 1

Later-stage markers take precedence over Stage1A safety logs, because Stage1A/1B remain active during later validation.

If the script reports a metric as `missing`, do not infer values from memory. State that the signal was not present in the audited log.
