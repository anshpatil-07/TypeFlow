# Phase 10: Continuous Learning and Auto-Correct - Context

**Gathered:** 2026-06-03
**Status:** Ready for planning

<domain>
## Phase Boundary

Implementing long-term typing habit personalization and inline auto-correction: silently capturing user sentence history and accepted completions locally, extracting custom jargon periodically in the background, few-shot prompt context injection, and delimiter-based auto-correction using NSSpellChecker.

</domain>

<decisions>
## Implementation Decisions

### History Logging & Privacy
- **D-01:** Capture naturally completed sentences ending in `.`, `?`, or `!` during typing (via `logSentenceFromText`).
- **D-02:** Capture combined sentences (`activeLine + completion`) when an LLM completion is accepted via Tab (via `logSentence`).
- **D-03:** Maintain a rolling window of the last 1,000 sentences.
- **D-04:** Personalization is strictly opt-in; no keystroke history is logged if the settings toggle is disabled.

### Storage Security
- **D-05:** Generate a secure 256-bit symmetric key on first launch and store it in the macOS Keychain (`kSecClassGenericPassword`).
- **D-06:** Serialize history as JSON and encrypt it using `CryptoKit`'s `AES.GCM` before writing to `history.enc` in the local Application Support directory.
- **D-07:** Decrypt logs in-memory on launch, retrieving the symmetric key from Keychain.

### Jargon & Vocab Extraction
- **D-08:** Run vocabulary extraction asynchronously on launch and periodically every 24 hours in the background.
- **D-09:** Filter out common English stopwords and identify the top 15 most frequent unique words (minimum 4 characters) that appear at least twice.
- **D-10:** Save computed vocabulary to `vocabulary.json` in the Application Support directory.

### Few-shot Prompt Construction
- **D-11:** Query history and rank matching sentences using basic keyword overlap (words >= 4 chars).
- **D-12:** Prepend up to 3 matched writing samples under a `[Past user writing samples]` block, backfilling with random samples from history if needed.
- **D-13:** Prepend the top 15 custom vocabulary keywords as a comma-separated list under a `[User vocabulary & jargon]` block.
- **D-14:** Only prepend these metadata blocks when personalization is enabled.

### Delimiter-based Auto-Correct
- **D-15:** Add a toggle in Settings UI (General tab): "Auto-correct misspelled words as you type".
- **D-16:** When the user types a word delimiter (Space, period, comma, !, ?), check if the completed word is misspelled using `NSSpellChecker` (minimum 4 characters).
- **D-17:** If auto-correct is enabled, automatically delete the misspelled word (calculating and injecting the correct number of backspaces), insert the corrected word, and append the typed delimiter.
- **D-18:** If auto-correct is disabled, fall back to displaying the correction as orange ghost text.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### App Context
- `.planning/PROJECT.md` — Core value constraints, architecture constraints.
- `.planning/REQUIREMENTS.md` — Requirements and current milestone details.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `SettingsManager.swift`: Handles persistent configuration, to be extended with `@AppStorage("personalizationEnabled")` and `@AppStorage("autoCorrectEnabled")`.
- `SettingsView.swift`: Displays Settings UI, to be extended with general personalization and auto-correct toggles.
- `CompletionManager.swift`: Central completion pipeline, to be hooked to trigger sentence logging and accepted completion logging.

### Established Patterns
- Local background helpers run on startup and schedule periodic timers.
- Local persistence in the Application Support directory under the `TypeFlow` subfolder.
- Key storage in macOS Keychain utilizing the `Security` framework.

### Integration Points
- `onTextChanged()`: Hooks into typing flow to check for completed words/delimiters and log typed sentences.
- `handleTabPressed()`: Hooks into tab acceptance to log the accepted completed sentence.
- `PromptBuilder.shared.buildPrompt(textBeforeCaret:)`: Prepend personalization blocks to the FIM prompt.

</code_context>

<specifics>
## Specific Ideas

No specific requirements — open to standard approaches.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 10-continuous-learning-and-auto-correct*
*Context gathered: 2026-06-03*
