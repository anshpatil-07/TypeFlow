# Phase 9: Completions Overhaul - Discussion Log

**Gathered:** 2026-05-23

## Questions and Answers

**Q1: Which areas do you want to discuss for Completions Overhaul?**
Selected:
- Generation Lifecycle
- Ghost Text Styling
- Tab Interception Strategy
- Edge Case Handling

**Q2: When should we cancel an in-flight LLM generation?**
Selected: Immediately cancel on any new keystroke (saves CPU/Battery)

**Q3: What should the debounce timing be before triggering generation?**
Selected: 150ms — aggressive, feels instant

**Q4: How should the ghost text visually match the target app?**
Selected: Use standard system font (SF Pro) with a generic gray color — robust and works everywhere

**Q5: Should the ghost text animate when appearing?**
Selected: No animation, just appear instantly — best for <150ms latency target

**Q6: How should the Tab key be intercepted when ghost text is visible?**
Selected: CGEvent tap (Intercepts globally before target app receives it)

**Q7: If Tab is pressed but NO ghost text is visible, what happens?**
Selected: Pass the Tab event through to the target app untouched

**Q8: If the model outputs nothing (or just whitespace), what should we do?**
Selected: Silently ignore it and hide any ghost text

**Q9: If the model starts generating text that exactly matches what the user is currently typing (echoing), what should we do?**
Selected: Strip the echoed prefix before displaying the ghost text
