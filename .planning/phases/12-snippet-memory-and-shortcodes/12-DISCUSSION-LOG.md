# Phase 12: Snippet Memory and Shortcodes - Discussion Log

**Date:** 2026-06-03

## Q&A Session Record

### Area: Dynamic Variables
1. **Question**: Which dynamic variables should be supported?
   - **Options**:
     - *(Recommended) Date, Time, Clipboard, and Cursor ({{date}}, {{time}}, {{clipboard}}, {{cursor}})* [SELECTED]
     - *Date and Clipboard only*
2. **Question**: What syntax should placeholders use?
   - **Options**:
     - *(Recommended) Double curly braces: {{variable}} (e.g., {{clipboard}})* [SELECTED]
     - *Bracket syntax: [variable] (e.g., [clipboard])*
3. **Question**: How should the {{cursor}} placeholder be implemented?
   - **Options**:
     - *(Recommended) Move cursor via Left Arrow events (calculate offset and inject arrow keys)* [SELECTED]
     - *Omit cursor positioning (just place caret at the end)*

### Area: Snippet Memory
1. **Question**: What criteria should be used to detect repeating phrases in typing history?
   - **Options**:
     - *(Recommended) Phrase minimum 20+ characters, appearing at least 3 times* [SELECTED]
     - *Phrase minimum 10+ characters, appearing at least 5 times*
2. **Question**: How should suggested snippets be presented to the user?
   - **Options**:
     - *(Recommended) Show in a "Suggestions" section/tab in Snippets Settings* [SELECTED]
     - *Show via a macOS notification banner*
3. **Question**: How should the shortcode be generated for suggestions?
   - **Options**:
     - *(Recommended) Generate a suggested abbreviation (e.g., prefixing first characters with '/')* [SELECTED]
     - *Leave shortcode field empty (require user input)*

### Area: Trigger Boundary
1. **Question**: What boundary condition should be enforced for shortcode matching?
   - **Options**:
     - *(Recommended) Match only when preceded by whitespace, punctuation, or start of line* [SELECTED]
     - *Match suffix anywhere (current behavior)*
2. **Question**: Should shortcodes require a prefix character?
   - **Options**:
     - *(Recommended) Prefix character required (e.g., must start with '/' or ';')* [SELECTED]
     - *No prefix character required (any plain text shortcode)*

### Area: Secure Storage
1. **Question**: How should snippets be encrypted?
   - **Options**:
     - *(Recommended) Encrypt the entire snippets dictionary (save to snippets.enc using Phase 10 key)* [SELECTED]
     - *Encrypt only the replacement values individually in Keychain*
2. **Question**: How should we handle existing unencrypted snippets from Phase 11?
   - **Options**:
     - *(Recommended) Automatically migrate existing snippets to the encrypted store on launch* [SELECTED]
     - *Do not migrate (discard existing snippets)*
