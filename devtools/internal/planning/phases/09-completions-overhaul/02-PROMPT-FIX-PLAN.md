---
wave: 2
depends_on: ["01-PIPELINE-OVERHAUL"]
files_modified: ["TypeFlow/Services/PromptBuilder.swift"]
autonomous: true
---

# Phase 9, Plan 2: Prompt Fix for Echoing

<objective>
Fix the issue where completions are completely non-functional. The root cause is that the LLM is still echoing the input text. Because the new prefix stripping logic in `CompletionManager` perfectly strips this echoed text, the resulting ghost text is completely empty (`""`). Thus, the user sees nothing even after waiting. We need to rewrite the prompt to forcefully prevent the LLM from echoing the input so it generates actual continuations.
</objective>

<requirements>
- TBD
</requirements>

<tasks>
<task>
  <description>Rewrite the LLM prompt to prevent echoing</description>
  <read_first>
    - TypeFlow/Services/PromptBuilder.swift
  </read_first>
  <action>
    1. In `TypeFlow/Services/PromptBuilder.swift`, rewrite the prompt heavily to enforce that the model MUST NOT repeat the input text.
    2. Add few-shot examples or strict `<instruction>` tags to show the model that it should only output the *continuation*.
    3. Example format to enforce:
       ```
       You are an autocomplete engine.
       [Text before cursor]: "The quick brown "
       [Continuation]: "fox jumps over"
       
       [Text before cursor]: {context.activeLineText}
       [Continuation]:
       ```
  </action>
  <acceptance_criteria>
    - `PromptBuilder.swift` contains a stricter prompt preventing echoes.
  </acceptance_criteria>
</task>
</tasks>
