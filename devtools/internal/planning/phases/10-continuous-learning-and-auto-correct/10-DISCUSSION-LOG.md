# Phase 10: Continuous Learning and Auto-Correct - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-06-03
**Phase:** 10-continuous-learning-and-auto-correct
**Areas discussed:** History Logging & Privacy, Storage Security, Jargon & Vocab Extraction, Few-shot Prompt Construction, Delimiter-based Auto-Correct

---

## History Logging & Privacy

| Option | Description | Selected |
|--------|-------------|----------|
| Lock in this logging & privacy design | Capture sentences on naturally typed boundary punctuation and completed tab completions, with a 1,000 sentence rolling window, and strictly respecting the opt-in toggle. | ✓ |
| Customize the logging & privacy design | Specify custom constraints. | |

**User's choice:** Lock in this logging & privacy design
**Notes:** Decided to keep the rolling window at 1,000 sentences and respect the `@AppStorage("personalizationEnabled")` toggle.

---

## Storage Security

| Option | Description | Selected |
|--------|-------------|----------|
| Lock in this storage security design | Generate a 256-bit symmetric key, store it in macOS Keychain, and encrypt the JSON array using AES.GCM before writing to history.enc. | ✓ |
| Customize the storage security design | Specify custom constraints. | |

**User's choice:** Lock in this storage security design
**Notes:** Using AES.GCM from CryptoKit coupled with keychain generic password is secure and private.

---

## Jargon & Vocab Extraction

| Option | Description | Selected |
|--------|-------------|----------|
| Lock in this jargon & vocab extraction design | Run daily and on startup, filter stopwords, select top 15 words >= 4 chars with frequency >= 2, and save to vocabulary.json. | ✓ |
| Customize the jargon & vocab extraction design | Specify custom constraints. | |

**User's choice:** Lock in this jargon & vocab extraction design
**Notes:** Stopword list covers most common English words, and the daily background extraction limits CPU usage.

---

## Few-shot Prompt Construction

| Option | Description | Selected |
|--------|-------------|----------|
| Lock in this prompt construction design | Use keyword overlap to match 3 writing samples (falling back to random), select top 15 vocabulary keywords, and format them as blocks before the FIM prompt. | ✓ |
| Customize the prompt construction design | Specify custom constraints. | |

**User's choice:** Lock in this prompt construction design
**Notes:** The blocks are prepended to the prompt only if personalization is active.

---

## Delimiter-based Auto-Correct

| Option | Description | Selected |
|--------|-------------|----------|
| Lock in this auto-correct design | Toggle in settings. Intercept word boundaries, check NSSpellChecker, delete misspelled word, inject correction and delimiter. Fall back to orange ghost text if disabled. | ✓ |
| Customize the auto-correct design | Specify custom constraints. | |

**User's choice:** Lock in this auto-correct design
**Notes:** Auto-correct toggle enables automatic injection on delimiters, preventing the need to hit Tab for simple typos.

---

## the agent's Discretion

None. All implementation paths were locked in based on prior plan.

## Deferred Ideas

None.
