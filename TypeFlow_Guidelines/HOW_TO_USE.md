# How to Manage AI Context in TypeFlow

1. **Standard Workflow:**
The `.cursorrules` file in the root directory is automatically read by the AI IDE. You do not need to do anything special for normal bug fixes. The AI knows not to touch the event tap or MLX cache.

2. **When the AI Breaks the App:**
If the AI ignores the rules and breaks the keystroke buffer or hallucination engine:
- Immediately run `git reset --hard` to revert to your last stable commit.
- Open `01_Nuclear_Strict_Prompt.md`.
- Copy the entire prompt.
- Replace `[INSERT YOUR SPECIFIC BUG HERE]` with what you were trying to accomplish.
- Paste the massive prompt into the AI chat to force absolute strictness.
