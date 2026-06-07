---
wave: 2
depends_on: [1]
files_modified:
  - TypeFlow/Services/NSServicesProvider.swift
  - TypeFlow/TypeFlowApp.swift
  - TypeFlow/Info.plist
autonomous: true
---

# Phase 19, Wave 2: macOS Native Services

## Objective
Implement a macOS Native Services provider to expose "Rewrite with TypeFlow" and "Expand with TypeFlow" to the system-wide right-click context menu.

## Tasks

<task>
<id>1</id>
<title>Implement NSServicesProvider</title>
<read_first>
- TypeFlow/Services/LLMEngine.swift (to see how to trigger generations)
</read_first>
<action>
1. Create `TypeFlow/Services/NSServicesProvider.swift`.
2. Implement an `@objc` class `NSServicesProvider`.
3. Add an `@objc` method for rewriting, e.g., `@objc func rewriteText(_ pboard: NSPasteboard, userData: String, error: AutoreleasingUnsafeMutablePointer<NSString>)`.
4. Add an `@objc` method for expanding, e.g., `@objc func expandText(_ pboard: NSPasteboard, userData: String, error: AutoreleasingUnsafeMutablePointer<NSString>)`.
5. These methods should extract string from `pboard`, process it via the LLM pipeline, and write the output back to `pboard`.
6. In `TypeFlowApp.swift`, register the service provider: `NSApp.servicesProvider = NSServicesProvider()`.
</action>
<acceptance_criteria>
- `NSServicesProvider.swift` exists and contains `@objc` methods with the correct `NSPasteboard` signatures.
- `NSApp.servicesProvider` is assigned on app startup.
</acceptance_criteria>
</task>

<task>
<id>2</id>
<title>Update Info.plist for NSServices</title>
<read_first>
- TypeFlow/Info.plist
</read_first>
<action>
1. Modify `TypeFlow/Info.plist` to include the `NSServices` array.
2. Add a dictionary for "Rewrite with TypeFlow":
   - `NSMenuItem`: `default` = `Rewrite with TypeFlow`
   - `NSMessage`: `rewriteText`
   - `NSPortName`: `TypeFlow`
   - `NSSendTypes`: `NSStringPboardType`
   - `NSReturnTypes`: `NSStringPboardType`
3. Add a dictionary for "Expand with TypeFlow":
   - `NSMenuItem`: `default` = `Expand with TypeFlow`
   - `NSMessage`: `expandText`
   - `NSPortName`: `TypeFlow`
   - `NSSendTypes`: `NSStringPboardType`
   - `NSReturnTypes`: `NSStringPboardType`
</action>
<acceptance_criteria>
- `Info.plist` contains the `NSServices` key with two items mapping to the correct methods (`rewriteText` and `expandText`).
</acceptance_criteria>
</task>

## Verification
<must_haves>
- `NSServicesProvider` correctly registered on launch.
- `Info.plist` advertises the services correctly to macOS.
</must_haves>
