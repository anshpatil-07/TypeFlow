# Codex Token-Saving Guidelines

Use medium reasoning by default. Use high reasoning only for root-cause investigations, architecture bugs, or changes with broad behavioral risk.

## Logs

- Do not paste raw logs into chat.
- Use the TypeFlow log auditor for TypeFlow logs:

```bash
python .agents/skills/typeflow-log-auditor/scripts/audit_typeflow_log.py <log-file>
```

- Default auditor output is a full Codex-style handoff report with metadata, stage-specific metrics, regression signals, examples, diagnosis, recommended next step, and missing metrics.
- Use `--compact` only for quick checks:

```bash
python .agents/skills/typeflow-log-auditor/scripts/audit_typeflow_log.py --compact <log-file>
```

- Log-audit and handoff reports may be longer than routine final reports when needed, but they must stay structured and compact.
- Prefer metrics and tables over prose.
- Cap representative raw log lines.
- Never paste full logs.

## Builds

- Redirect full `xcodebuild` output to a file.
- On build success, report only success.
- On failure, report only the command and the relevant final error section.

## Git

Use compact git commands:

```bash
git status --short
git diff --stat
git diff -- <specific files>
```

## Reports

- Routine final reports should be concise, ideally under 12 bullets.
- Exception: log-audit and handoff reports may be longer when needed, but must remain structured and compact.
- Include enough detail for the next agent to continue without rereading large raw artifacts.

## RTK command-output compression

RTK is installed locally and should be used for noisy shell inspection when available.

Prefer compact/RTK-wrapped commands:
- rtk git status --short
- rtk git diff --stat
- rtk git diff -- <specific files>
- rtk rg <pattern> <paths>
- rtk ls
- rtk cat <small file only>

For build/test/log workflows:
- redirect full xcodebuild output to a local log file
- report only success/failure, or the relevant final error section on failure
- use the TypeFlow log auditor for TypeFlow logs
- never paste full raw logs
- never paste full raw build output

RTK helps reduce command-output tokens. It does not reduce reasoning tokens, long prompts, old chat history, or huge text pasted directly into chat.
