# Phase 11: Tone Profiles - Discussion Log

This document records the Q&A session conducted on 2026-06-03 to align on the scope and design preferences for the Tone Profiles feature.

## Q&A Records

### 1. UI Integration Location
- **Question**: Where should the custom tone creation and management UI live in the Settings window?
- **Options**:
  - Replace the 'Persona' tab with a 'Tones' tab that lists all tones (built-in and custom) in a list/sidebar for creation and management (Recommended)
  - Add a completely new 'Tones' tab alongside the existing 'Persona' and 'General' tabs
  - Add a 'Manage Tones' button/popup directly within the 'General' tab under the Completion Tone picker
- **User Selection**: Replace the 'Persona' tab with a 'Tones' tab that lists all tones (built-in and custom) in a list/sidebar for creation and management.

### 2. Configuration Parameters
- **Question**: What configuration parameters should each tone profile contain?
- **Options**:
  - Name, custom system instructions, temperature (creativity slider), and max token length (Recommended)
  - Strictly minimal: Name and custom system instructions only
  - Comprehensive: Name, instructions, temperature, max token length, and custom stop sequences
- **User Selection**: Name, custom system instructions, temperature (creativity slider), and max token length.

### 3. Built-in vs Custom Tones Behavior
- **Question**: How should the default built-in tones (Neutral, Professional, Casual, Concise) behave?
- **Options**:
  - Built-in tones are read-only defaults. They cannot be edited or deleted, but users can duplicate them. Only custom tones can be fully edited/deleted. (Recommended)
  - Built-in tones can have their instructions/parameters edited, but they cannot be deleted.
  - Full flexibility: Built-in tones can be deleted, renamed, or modified just like custom tones.
- **User Selection**: Built-in tones are read-only defaults. They cannot be edited or deleted, but users can duplicate them. Only custom tones can be fully edited/deleted.

### 4. App Overrides Integration
- **Question**: Should custom tone profiles be assignable to specific applications in App Overrides?
- **Options**:
  - Dynamically populate the Tone picker in App Overrides (Apps tab) with all custom tone profiles in addition to the built-in ones, using the tone ID/name for association (Recommended)
  - Restrict App Overrides to only the default built-in tones (custom tone profiles cannot be assigned per-app)
- **User Selection**: Dynamically populate the Tone picker in App Overrides (Apps tab) with all custom tone profiles in addition to the built-in ones, using the tone ID/name for association.
