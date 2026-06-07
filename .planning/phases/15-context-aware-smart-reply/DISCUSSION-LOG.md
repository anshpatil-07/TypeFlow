# Phase 15: Context-Aware Smart Reply - Discussion Log

**Date:** 2026-06-04

## Q1: Which areas do you want to discuss for Context-Aware Smart Reply?
**Options:**
- (Recommended) UI Presentation — Ghost text cycle vs Popover options? (Popover exists from Phase 14)
- Trigger Mechanism — Automatic on empty field vs manual shortcut?
- Context Extraction — Full screen OCR vs active window only?
- Tone Selection — Use default tone vs quick-pick in UI?
**User Selection:**
- All 4 areas selected.

## Q2: How should the smart replies be presented?
**Options:**
- (Recommended) Popover with 3 options (Reuses Phase 14 Rewrite UI pattern, user clicks/selects one)
- Ghost text cycling (Hit arrow keys to cycle through options inline)
- Native macOS context menu below caret
**User Selection:**
- (Recommended) Popover with 3 options (Reuses Phase 14 Rewrite UI pattern, user clicks/selects one)

## Q3: How should Context-Aware Smart Reply be triggered?
**Options:**
- (Recommended) Manual global shortcut (e.g., Cmd+Shift+R) (Predictable, avoids accidental popovers)
- Automatic when focusing an empty text field in whitelisted apps (e.g. Messages, Mail)
- Both (Shortcut everywhere, automatic in whitelisted apps)
**User Selection:**
- (Recommended) Manual global shortcut (e.g., Cmd+Shift+R) (Predictable, avoids accidental popovers)

## Q4: How should the tone of the smart reply be determined?
**Options:**
- (Recommended) Always generate 3 diverse options (e.g., Professional, Casual, Concise) and let user pick.
- Use the currently active Tone Profile set in Settings/App Overrides to generate 3 variations of that tone.
- Add quick-pick tone buttons to the popover to regenerate the replies.
**User Selection:**
- (Recommended) Always generate 3 diverse options (e.g., Professional, Casual, Concise) and let user pick.

## Q5: How should we extract the conversation context to generate the reply?
**Options:**
- (Recommended) Both: Combine Accessibility API text + recent Vision OCR text from ScreenContextManager (Most comprehensive)
- Only Accessibility API text (Faster, but might miss non-native UI text)
- Only Vision OCR text (Catches everything visible, slightly slower)
**User Selection:**
- (Recommended) Both: Combine Accessibility API text + recent Vision OCR text from ScreenContextManager (Most comprehensive)

## Q6: We've discussed UI Presentation, Trigger Mechanism, Tone Selection, and Context Extraction. Which gray areas remain unclear?
**User Selection:**
- I'm ready for context
