---
wave: 1
depends_on: []
files_modified:
  - TypeFlow/Services/ClipboardMonitor.swift
  - TypeFlow/TypeFlowApp.swift
  - TypeFlow/Services/PromptBuilder.swift
autonomous: true
---

# Phase 19, Wave 1: Clipboard Integration

## Objective
Create a rolling clipboard monitor that stores the last 3 unique items and injects them into the LLM context if trigger phrases are detected.

## Tasks

<task>
<id>1</id>
<title>Implement ClipboardMonitor</title>
<read_first>
- TypeFlow/Services/PromptBuilder.swift (to understand context requirements)
</read_first>
<action>
1. Create `TypeFlow/Services/ClipboardMonitor.swift`.
2. Implement `ClipboardMonitor` as an `@Observable` or shared singleton class.
3. Start a timer or notification observer to poll `NSPasteboard.general.changeCount`.
4. Maintain an array `recentItems: [String]` of the last 3 unique text items copied.
5. Limit each stored item to a maximum of 500 characters to prevent memory bloat.
6. Initialize and start the monitor in `TypeFlowApp.swift` or wherever background services are bootstrapped.
</action>
<acceptance_criteria>
- `ClipboardMonitor.swift` exists and compiles.
- Contains an array storing up to 3 strings.
- Items over 500 characters are truncated.
- Changes in `NSPasteboard` update the array.
</acceptance_criteria>
</task>

<task>
<id>2</id>
<title>Inject Clipboard Context in PromptBuilder</title>
<read_first>
- TypeFlow/Services/PromptBuilder.swift
- TypeFlow/Services/ClipboardMonitor.swift
</read_first>
<action>
1. Open `TypeFlow/Services/PromptBuilder.swift`.
2. Locate where the system prompt / context is constructed.
3. Add a check: if `textBeforeCaret` ends with clipboard-seeking trigger phrases (e.g., "Here is the link: ", "my email is ", "the code is ", "paste it: "), retrieve items from `ClipboardMonitor`.
4. Append the clipboard items to the prompt context, e.g., `[Recent Clipboard Items]: \n- item1\n- item2`.
</action>
<acceptance_criteria>
- `PromptBuilder.swift` contains logic to check `textBeforeCaret` for trigger phrases.
- The context string includes `[Recent Clipboard Items]` when a trigger phrase is detected.
</acceptance_criteria>
</task>

## Verification
<must_haves>
- `ClipboardMonitor` correctly limits stored items to 3 unique entries and truncates to 500 chars.
- `PromptBuilder` conditionally injects clipboard contents based on trigger phrases in the active text field.
</must_haves>
