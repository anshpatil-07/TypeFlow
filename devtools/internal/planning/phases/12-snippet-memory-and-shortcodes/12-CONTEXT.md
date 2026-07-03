# Phase 12: Snippet Memory and Shortcodes - Context

**Gathered:** 2026-06-03
**Status:** Ready for planning

<domain>
## Phase Boundary

Implementing dynamic shortcode variables and automatic snippet learning: extending snippets to support `{{date}}`, `{{time}}`, `{{clipboard}}`, and `{{cursor}}` dynamic placeholders; checking word boundaries and requiring a prefix character (like `/`) to prevent accidental shortcode expansion; automatically detecting repeating phrases from local typing history and suggesting them to the user in the Settings UI; and encrypting the snippets database locally using the keychain symmetric key.

</domain>

<decisions>
## Implementation Decisions

### 1. Dynamic Variables (Shortcodes)
- **D-01**: Support the following inline variables within snippet replacements:
  - `{{date}}`: Expands to current date in YYYY-MM-DD format.
  - `{{time}}`: Expands to current time in HH:MM format.
  - `{{clipboard}}`: Expands to current clipboard text content.
  - `{{cursor}}`: Moves the keyboard cursor (caret) to this position after injection.
- **D-02**: Placeholder syntax will strictly use double curly braces: `{{variable}}`.
- **D-03**: The `{{cursor}}` tag will position the cursor by calculating the offset from the end of the expanded text and posting Left Arrow keyboard CGEvents.

### 2. Snippet Memory (Auto-Suggestion)
- **D-04**: Analyze local typing history (e.g. during vocabulary extraction or startup) to detect repeating phrases.
- **D-05**: Match phrases of minimum length 20+ characters that have appeared at least 3 times.
- **D-06**: Display candidate suggestions in a new "Suggestions" section of the Snippets Settings tab, allowing the user to approve them and customize the shortcode.
- **D-07**: Suggestion abbreviations are auto-generated (e.g., prefixing first characters with `/`), but the user must confirm or change it.

### 3. Trigger Boundary (Expansion UX)
- **D-08**: Shortcodes must start with a prefix character (specifically `/` or `;`).
- **D-09**: Match shortcodes on word boundaries only (preceded by whitespace, punctuation, or start of line) to prevent accidental expansions.

### 4. Secure Storage
- **D-10**: Encrypt the entire snippets dictionary and save it to `snippets.enc` in the local Application Support directory, using the AES-GCM 256-bit symmetric key retrieved from the Keychain (sharing the same key as the typing history log).
- **D-11**: On startup, automatically migrate any existing plaintext snippets data from `@AppStorage("snippetsData")` into the encrypted `snippets.enc` file and clear the plaintext storage key.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Settings & UI
- `TypeFlow/UI/SettingsView.swift` — Defines Settings tab layouts and bindings.
- `TypeFlow/Services/SettingsManager.swift` — Stores configurations and App Storage values.

### Completion & Text Injection
- `TypeFlow/Services/CompletionManager.swift` — Managing completion pipelines and shortcodes.
- `TypeFlow/Services/TextInjector.swift` — Injecting characters and backspaces.
- `TypeFlow/Services/AccessibilityMonitor.swift` — Keystroke buffering and text selection extraction.

</canonical_refs>

<specifics>
## Specific Ideas
- Snippet suggestions should be ranked by frequency and presented in a scrollable list.
</specifics>

<deferred>
## Deferred Ideas
- None — all discussed scope falls within Phase 12.
</deferred>
