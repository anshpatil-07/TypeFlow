---
wave: 1
depends_on: []
files_modified:
  - TypeFlow/Services/SettingsManager.swift
  - TypeFlow/Services/CompletionManager.swift
  - TypeFlow/Services/TextInjector.swift
  - TypeFlow/Services/TypingHistoryManager.swift
  - TypeFlow/UI/SettingsView.swift
autonomous: true
---

# Plan 12: Snippet Memory and Shortcodes

## Objective
Implement dynamic shortcode variables and automatic snippet learning: extending snippets to support `{{date}}`, `{{time}}`, `{{clipboard}}`, and `{{cursor}}` placeholders; enforcing prefix requirements and word boundary checks for snippet matching; automatically extracting repeating phrases from typing history as suggestions; and securing snippet storage via AES-GCM encryption.

## Requirements Addressed
- **SNIP-01**: Support dynamic placeholders (`{{date}}`, `{{time}}`, `{{clipboard}}`, `{{cursor}}`) in replacements. Caret positioning via arrow keys for `{{cursor}}`.
- **SNIP-02**: Enforce word-boundary checks and trigger character requirements (prefixed with `/` or `;`).
- **SNIP-03**: Secure storage of snippets (JSON AES-GCM encrypted in `snippets.enc` using KeyChain key) with seamless launch migration.
- **SNIP-04**: Snippet Memory (periodically analyze typing history for repetitive patterns of length 20+ chars, occurring 3+ times, and auto-suggest them in Settings UI).

## Tasks

<task>
<id>secure-storage-snippets</id>
<description>Refactor snippet storage in SettingsManager to use an encrypted JSON file snippets.enc in Application Support, encrypted with the 256-bit Keychain symmetric key. Add a migration step to automatically move existing plaintext snippets on launch.</description>
<read_first>
- TypeFlow/Services/SettingsManager.swift
- TypeFlow/Services/TypingHistoryManager.swift
</read_first>
<action>
1. In `SettingsManager.swift`, add an encryption/decryption key retrieval method reusing the Keychain key `"com.cotyper.TypeFlow.historyKey"` from `KeychainHelper` (defined in `TypingHistoryManager.swift` or refactored as helper).
2. Set up the file path for `snippets.enc` in the local Application Support directory:
   ```swift
   let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
   let typeFlowDir = appSupport.appendingPathComponent("TypeFlow")
   let snippetsFileURL = typeFlowDir.appendingPathComponent("snippets.enc")
   ```
3. Implement `getSnippets()` and `saveSnippets(_:)` to read/write `snippets.enc` using `CryptoKit`'s `AES.GCM` encryption.
4. Add a migration step in `getSnippets()` or `SettingsManager.init()`: if the unencrypted `UserDefaults` key `"snippetsData"` contains data, decode it, save it using the new encrypted file system, and clear the `"snippetsData"` key from `UserDefaults` to ensure no plaintext backup is left.
</action>
<acceptance_criteria>
- `SettingsManager.swift` contains code to read and write snippets from/to `snippets.enc` using `AES.GCM`.
- Plaintext snippets data in `@AppStorage("snippetsData")` is automatically migrated and removed from `UserDefaults` on launch.
</acceptance_criteria>
</task>

<task>
<id>boundary-matching-and-prefix</id>
<description>Modify shortcode detection in CompletionManager to require that shortcodes start with / or ; and are only expanded when preceded by a word boundary (whitespace, punctuation, or start of line).</description>
<read_first>
- TypeFlow/Services/CompletionManager.swift
- TypeFlow/Services/AccessibilityMonitor.swift
</read_first>
<action>
1. In `CompletionManager.swift`, update the snippet check inside `onTextChanged()` and `handleTabPressed()`.
2. Require that keys match only if they start with `/` or `;`.
3. Check that the character immediately preceding the typed shortcode in the active text line is a word boundary:
   - A helper function:
     ```swift
     func hasWordBoundaryBeforeSuffix(activeLine: String, suffix: String) -> Bool {
         guard activeLine.hasSuffix(suffix) else { return false }
         let prefixLength = activeLine.count - suffix.count
         guard prefixLength > 0 else { return true } // Start of line is a boundary
         let index = activeLine.index(activeLine.startIndex, offsetBy: prefixLength - 1)
         let charBefore = activeLine[index]
         return charBefore.isWhitespace || charBefore.isPunctuation
     }
     ```
</action>
<acceptance_criteria>
- Shortcode expansion only triggers when the snippet key starts with `/` or `;`.
- Shortcode expansion only triggers when the shortcode is preceded by whitespace, punctuation, or the start of the line.
</acceptance_criteria>
</task>

<task>
<id>dynamic-placeholders-and-cursor</id>
<description>Implement support for dynamic variables {{date}}, {{time}}, {{clipboard}}, and caret positioning using {{cursor}} via Left Arrow event injection.</description>
<read_first>
- TypeFlow/Services/CompletionManager.swift
- TypeFlow/Services/TextInjector.swift
</read_first>
<action>
1. In `CompletionManager.swift`, resolve placeholders in the replacement template before injection:
   - Replace `{{date}}` with the current date in YYYY-MM-DD format.
   - Replace `{{time}}` with the current time in HH:MM format.
   - Replace `{{clipboard}}` with the current clipboard string contents (using `NSPasteboard.general.string(forType: .string)`).
2. Resolve `{{cursor}}`:
   - Find the offset (number of characters) from the `{{cursor}}` placeholder position to the end of the fully expanded replacement string.
   - Strip the `{{cursor}}` tag from the final replacement text.
   - Pass the calculated offset to `TextInjector.shared.inject(text: replacementText, moveCursorBackCount: offset)`.
3. In `TextInjector.swift`, update `inject(text:)` to support moving the caret back by injecting Left Arrow `CGEvent` instances (virtualKey 123) with user data `9999` to bypass trigger checks:
   ```swift
   func inject(text: String, moveCursorBackCount: Int) {
       inject(text: text) // inject characters
       
       if moveCursorBackCount > 0 {
           guard let source = CGEventSource(stateID: .combinedSessionState) else { return }
           for _ in 0..<moveCursorBackCount {
               if let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 123, keyDown: true) {
                   keyDown.setIntegerValueField(.eventSourceUserData, value: 9999)
                   keyDown.post(tap: .cgSessionEventTap)
               }
               if let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 123, keyDown: false) {
                   keyUp.setIntegerValueField(.eventSourceUserData, value: 9999)
                   keyUp.post(tap: .cgSessionEventTap)
               }
           }
       }
   }
   ```
</action>
<acceptance_criteria>
- Dynamic variables `{{date}}`, `{{time}}`, and `{{clipboard}}` expand to their correct dynamic values during injection.
- Snippets containing `{{cursor}}` result in the caret being repositioned at the placeholder location.
</acceptance_criteria>
</task>

<task>
<id>snippet-memory-detection</id>
<description>Extend TypingHistoryManager to analyze stored typing history for repetitive patterns (minimum 20+ characters, appearing 3+ times) and expose them as suggested snippets.</description>
<read_first>
- TypeFlow/Services/TypingHistoryManager.swift
</read_first>
<action>
1. Implement a method `getSuggestedSnippets() -> [(text: String, suggestedShortcode: String)]` in `TypingHistoryManager.swift` that scans the stored sentences list:
   - Identify sentences or phrases (length >= 20 characters) that occur 3 or more times.
   - Filter out phrases that are already present in the active snippets database.
2. For each recommendation, generate a candidate shortcode by taking the first few characters of the phrase, prefixing with `/` (e.g. "Best regards" -> `/bes`).
</action>
<acceptance_criteria>
- `TypingHistoryManager.swift` contains the method `getSuggestedSnippets()`.
- Suggestions are successfully filtered to exclude existing snippets and limit to repetitive patterns (length >= 20, count >= 3).
</acceptance_criteria>
</task>

<task>
<id>settings-ui-suggestions</id>
<description>Update SettingsView in the Snippets tab to display suggested snippets and allow the user to approve and add them to their active snippets list.</description>
<read_first>
- TypeFlow/UI/SettingsView.swift
</read_first>
<action>
1. In `SettingsView.swift`, modify `SnippetsSettingsView` to fetch and render the suggestions list from `TypingHistoryManager.shared.getSuggestedSnippets()`.
2. Add a list of suggestions showing the text, the prefilled candidate shortcode in a TextField, and an "Add" button to register it.
</action>
<acceptance_criteria>
- The Snippets settings UI displays suggested snippets from the history log.
- Clicking the "Add" button successfully adds the suggestion with the chosen shortcode to the encrypted snippets database.
</acceptance_criteria>
</task>

## Must Haves
- Snippets database must be encrypted with the Keychain 256-bit symmetric key and unencrypted legacy settings must migrate automatically.
- Dynamic variables `{{date}}`, `{{time}}`, `{{clipboard}}`, and caret positioning `{{cursor}}` must expand correctly.
- Word boundary matching and prefix requirements must be enforced to prevent false triggers.
- Suggested snippets section must show repetitively typed phrases from local history with custom shortcode fields.

## Verification
- Add a test runner script (`TypeFlow/scratch/test_snippets.swift`) to verify encryption/decryption, placeholder resolution, trigger boundary checks, and suggestion retrieval.
- Manually run the app, verify migration, test variable expansions in text editors, and confirm suggested snippets show up under the Snippets Settings tab.
