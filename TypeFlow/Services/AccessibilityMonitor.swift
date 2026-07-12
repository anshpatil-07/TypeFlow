import Cocoa

enum TextBeforeCaretSource: String {
    case axValue = "AXValue"
    case axSelectedText = "AXSelectedText"
    case axStringForRange = "AXStringForRange"
    case keystrokeBufferFallback = "keystrokeBufferFallback"
    case providedText = "providedText"
    case none = "none"
}

struct TextBeforeCaretSnapshot {
    let text: String
    let source: TextBeforeCaretSource
}

enum InputIsolationMode: String {
    case normal
    case modeA = "A"
    case modeB = "B"
    case modeC = "C"
    case modeD = "D"
    case modeE = "E"
    case modeF = "F"

    static let current: InputIsolationMode = {
        let args = ProcessInfo.processInfo.arguments
        let envMode = ProcessInfo.processInfo.environment["TF_INPUT_MODE"]
        let argMode = args.compactMap { arg -> String? in
            if arg.hasPrefix("--tf-input-mode=") {
                return String(arg.dropFirst("--tf-input-mode=".count))
            }
            if arg.hasPrefix("-tfInputMode=") {
                return String(arg.dropFirst("-tfInputMode=".count))
            }
            return nil
        }.last

        let rawMode = (argMode ?? envMode ?? "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return InputIsolationMode(rawValue: rawMode) ?? .normal
    }()

    var isDiagnostic: Bool { self != .normal }
    var label: String { self == .normal ? "normal" : rawValue }

    var installObserverTap: Bool {
        switch self {
        case .normal, .modeB, .modeD, .modeE, .modeF: return true
        case .modeA, .modeC: return false
        }
    }

    var installAcceptTapAtLaunch: Bool {
        switch self {
        case .modeC: return true
        case .normal, .modeA, .modeB, .modeD, .modeE, .modeF: return false
        }
    }

    var acceptTapPassThroughOnly: Bool { self == .modeC }
    var observerTapPassThroughOnly: Bool { self == .modeB || self == .modeD }
    var allowObserverProcessing: Bool { self == .normal || self == .modeE || self == .modeF }
    var allowAXObserver: Bool { self == .normal || self == .modeD || self == .modeE || self == .modeF }
    var allowFocusAuditAXPolling: Bool { self == .normal || self == .modeD || self == .modeE || self == .modeF }
    var allowOverlay: Bool { self == .normal || self == .modeE || self == .modeF }
    var allowGeneration: Bool { self == .normal || self == .modeE || self == .modeF }
    var allowAncillaryStartup: Bool { self == .normal || self == .modeE || self == .modeF }
    var allowTextInjectorTapChecks: Bool { self == .normal || self == .modeE || self == .modeF }
    var prewarmTextInjector: Bool { self == .normal || self == .modeE || self == .modeF }
    var allowDynamicAcceptTap: Bool { self == .normal || self == .modeE || self == .modeF }

    var summary: String {
        "mode=\(label) observerTapInstalled=\(installObserverTap) observerTapLocation=cgSessionEventTap observerTapOptions=listenOnly acceptTapInstalledAtLaunch=\(installAcceptTapAtLaunch) acceptTapLocation=cgSessionEventTap acceptTapOptions=defaultTap acceptTapPassThroughOnly=\(acceptTapPassThroughOnly) observerPassThroughOnly=\(observerTapPassThroughOnly) axObserverAllowed=\(allowAXObserver) axPollingAllowed=\(allowFocusAuditAXPolling) overlayAllowed=\(allowOverlay) generationAllowed=\(allowGeneration) ancillaryStartupAllowed=\(allowAncillaryStartup)"
    }
}

final class InputCriticalSection {
    static let shared = InputCriticalSection()

    private let lock = NSLock()
    private var downKeys: [Int64: String] = [:]
    private var pendingSafeCallbacks: [() -> Void] = []
    private var pendingImmediateSafeCallbacks: [() -> Void] = []
    private let flushDelay: TimeInterval = 0.02

    private init() {}

    var isActive: Bool {
        lock.lock()
        let active = !downKeys.isEmpty
        lock.unlock()
        return active
    }

    var activeDepth: Int {
        lock.lock()
        let depth = downKeys.count
        lock.unlock()
        return depth
    }

    func begin(keyCode: Int64, chars: String) {
        let label = chars.isEmpty ? "keyCode=\(keyCode)" : chars
        lock.lock()
        downKeys[keyCode] = label
        let depth = downKeys.count
        lock.unlock()

        print("[InputCriticalSection] keyDown \(label) -> begin depth=\(depth)")

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.forceEndIfStillDown(keyCode: keyCode, chars: label)
        }
    }

    func end(keyCode: Int64, chars: String) {
        let label = chars.isEmpty ? "keyCode=\(keyCode)" : chars
        var callbacks: [() -> Void] = []
        var immediateCallbacks: [() -> Void] = []

        lock.lock()
        downKeys.removeValue(forKey: keyCode)
        let depth = downKeys.count
        if depth == 0 {
            immediateCallbacks = pendingImmediateSafeCallbacks
            pendingImmediateSafeCallbacks.removeAll()
            callbacks = pendingSafeCallbacks
            pendingSafeCallbacks.removeAll()
        }
        lock.unlock()

        print("[InputCriticalSection] keyUp \(label) -> end depth=\(depth)")

        if !immediateCallbacks.isEmpty {
            DispatchQueue.main.async {
                print("[InputCriticalSection] flushed/deferred overlay update after keyUp immediateCallbacks=\(immediateCallbacks.count)")
                immediateCallbacks.forEach { $0() }
            }
        }

        if !callbacks.isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + flushDelay) {
                print("[InputCriticalSection] flushed/deferred overlay update after keyUp callbacks=\(callbacks.count)")
                callbacks.forEach { $0() }
            }
        }
    }

    func runWhenSafe(_ callback: @escaping () -> Void, immediateAfterDepthZero: Bool = false) {
        var runNow = false

        lock.lock()
        if downKeys.isEmpty {
            runNow = true
        } else if immediateAfterDepthZero {
            pendingImmediateSafeCallbacks.append(callback)
        } else {
            pendingSafeCallbacks.append(callback)
        }
        lock.unlock()

        if runNow {
            DispatchQueue.main.async(execute: callback)
        }
    }

    private func forceEndIfStillDown(keyCode: Int64, chars: String) {
        var callbacks: [() -> Void] = []
        var immediateCallbacks: [() -> Void] = []
        var didForce = false

        lock.lock()
        if downKeys.removeValue(forKey: keyCode) != nil {
            didForce = true
            if downKeys.isEmpty {
                immediateCallbacks = pendingImmediateSafeCallbacks
                pendingImmediateSafeCallbacks.removeAll()
                callbacks = pendingSafeCallbacks
                pendingSafeCallbacks.removeAll()
            }
        }
        lock.unlock()

        guard didForce else { return }
        print("[InputCriticalSection] key \(chars) force-ended after timeout")

        if !immediateCallbacks.isEmpty {
            DispatchQueue.main.async {
                print("[InputCriticalSection] flushed/deferred overlay update after forced end immediateCallbacks=\(immediateCallbacks.count)")
                immediateCallbacks.forEach { $0() }
            }
        }

        if !callbacks.isEmpty {
            DispatchQueue.main.async {
                print("[InputCriticalSection] flushed/deferred overlay update after forced end callbacks=\(callbacks.count)")
                callbacks.forEach { $0() }
            }
        }
    }
}

class AccessibilityMonitor {
    var observerTap: CFMachPort?
    var observerRunLoopSource: CFRunLoopSource?
    
    var acceptTap: CFMachPort?
    var acceptRunLoopSource: CFRunLoopSource?
    var pendingDisableReason: String? = nil
    
    var onCaretMoved: ((CGRect) -> Void)?
    private var retryTimer: Timer?
    var keystrokeBuffer: String = ""
    private var activeAppObserver: AXObserver?
    /// PID of the application whose AX observer is currently registered.
    /// Used to suppress intra-app focus-change noise (e.g. browser URL bar ↔ page).
    var activeFocusPID: pid_t = 0
    private let processingQueue = DispatchQueue(label: "com.cotyper.eventProcessing", qos: .utility)
    // Dedicated serial queue for the CGEventTap observer callback. Isolates all
    // event-handling work from the main run loop and the LLM pipeline queues,
    // ensuring the event tap thread returns instantly and macOS never drops events.
    private let tapQueue = DispatchQueue(label: "com.cotyper.tapCallback", qos: .userInteractive)
    private let inputAuditQueue = DispatchQueue(label: "com.cotyper.inputAudit", qos: .utility)
    private var contextFetchWorkItem: DispatchWorkItem?
    private let pendingNormalKeyLock = NSLock()
    private struct PendingPrintableKey {
        let keyCode: Int64
        let chars: String
        let oldBuffer: String
        let event: CGEvent
        let keyDownTimestamp: UInt64
    }
    private var pendingPrintableKeys: [Int64: PendingPrintableKey] = [:]
    
    private var lastDeletedWord: String?
    private var isBackspacing = false
    private let editableElementLock = NSLock()
    private var lastEditableElement: AXUIElement?
    private var lastEditableElementPID: pid_t = 0
    private var lastEditableElementRole: String = ""
    private var lastEditableElementTimestamp: CFAbsoluteTime = 0

    var activeEditableElement: AXUIElement? {
        editableElementLock.lock()
        defer { editableElementLock.unlock() }
        return lastEditableElement
    }

    private struct EditableElementResolution {
        let element: AXUIElement
        let source: String
        let role: String
        let subrole: String
        let pid: pid_t
        let isRecovered: Bool
    }

    private func contextAuditPreview(_ text: String, limit: Int = 180) -> String {
        let escaped = text
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\t", with: "\\t")
        if escaped.count <= limit { return escaped }
        return "..." + String(escaped.suffix(limit))
    }

    private func logContextAudit(_ message: String) {
        print("[TypeFlow-ContextAudit] \(message)")
    }

    private func escapedForInputAudit(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\t", with: "\\t")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "'", with: "\\'")
    }

    private func unicodeString(from event: CGEvent) -> String {
        var actualLength = 0
        var unicodeChars = [UniChar](repeating: 0, count: 16)
        event.keyboardGetUnicodeString(maxStringLength: 16, actualStringLength: &actualLength, unicodeString: &unicodeChars)
        guard actualLength > 0 else { return "" }
        return String(utf16CodeUnits: unicodeChars, count: actualLength)
    }

    private func eventTypeName(_ type: CGEventType) -> String {
        switch type {
        case .keyDown: return "keyDown"
        case .keyUp: return "keyUp"
        default: return "\(type.rawValue)"
        }
    }

    private func enqueueInputAudit(
        tap: String,
        type: CGEventType,
        event: CGEvent,
        action: String,
        matchedShortcut: Bool,
        originalReturned: Bool,
        callbackStart: CFAbsoluteTime,
        completionActive: Bool,
        overlayVisible: Bool,
        currentCompletionNonEmpty: Bool,
        modified: Bool = false,
        reposted: Bool = false,
        syntheticEmitted: Bool = false
    ) {
        guard type == .keyDown || type == .keyUp else { return }

        let callbackDurationMs = (CFAbsoluteTimeGetCurrent() - callbackStart) * 1000.0
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let characters = unicodeString(from: event)
        let charactersIgnoringModifiers = characters
        let modifiers = String(event.flags.rawValue, radix: 16)
        let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        let timestamp = event.timestamp
        let eventType = eventTypeName(type)
        let swallowed = !originalReturned
        let focusedPID = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0
        let textInjectorRecent = InputIsolationMode.current.allowTextInjectorTapChecks
            ? TextInjector.shared.syntheticEventWithinLast(milliseconds: 500)
            : false

        inputAuditQueue.async { [weak self] in
            guard let self = self else { return }
            print("[TypeFlow-InputAudit] tap=\(tap) eventType=\(eventType) keyCode=\(keyCode) chars='\(self.escapedForInputAudit(characters))' charsIgnoringModifiers='\(self.escapedForInputAudit(charactersIgnoringModifiers))' modifiers=0x\(modifiers) isARepeat=\(isRepeat) timestamp=\(timestamp) focusedPID=\(focusedPID) action=\(action) completionActive=\(completionActive) overlayVisible=\(overlayVisible) currentCompletionNonEmpty=\(currentCompletionNonEmpty) matchedShortcut=\(matchedShortcut) modified=\(modified) swallowed=\(swallowed) reposted=\(reposted) originalReturned=\(originalReturned) syntheticEmitted=\(syntheticEmitted) textInjectorWithin500ms=\(textInjectorRecent) callbackDurationMs=\(String(format: "%.3f", callbackDurationMs))")
        }
    }

    private func focusedElementAuditSummary() -> String {
        let systemWideElement = AXUIElementCreateSystemWide()
        var focusedElement: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(systemWideElement, kAXFocusedUIElementAttribute as CFString, &focusedElement)
        guard err == .success, let element = focusedElement else {
            return "err=\(err.rawValue)"
        }

        let axElement = element as! AXUIElement
        var pid: pid_t = 0
        AXUIElementGetPid(axElement, &pid)

        func attr(_ name: CFString) -> String {
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(axElement, name, &value) == .success, let value else {
                return ""
            }
            return String(describing: value)
        }

        let role = attr(kAXRoleAttribute as CFString)
        let subrole = attr(kAXSubroleAttribute as CFString)
        let title = attr(kAXTitleAttribute as CFString)
        let rolePart = role.isEmpty ? "unknown" : role
        let subrolePart = subrole.isEmpty ? "none" : subrole
        let titlePart = title.isEmpty ? "none" : contextAuditPreview(title, limit: 80)
        return "pid=\(pid) role='\(escapedForInputAudit(rolePart))' subrole='\(escapedForInputAudit(subrolePart))' title='\(escapedForInputAudit(titlePart))'"
    }

    private func focusedEditableElementState() -> (pid: pid_t, role: String, subrole: String, isEditable: Bool)? {
        let systemWideElement = AXUIElementCreateSystemWide()
        var focusedElement: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(systemWideElement, kAXFocusedUIElementAttribute as CFString, &focusedElement)
        guard err == .success, let element = focusedElement else { return nil }

        let axElement = element as! AXUIElement
        var pid: pid_t = 0
        AXUIElementGetPid(axElement, &pid)

        func attr(_ name: CFString) -> String {
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(axElement, name, &value) == .success, let value else {
                return ""
            }
            return String(describing: value)
        }

        let role = attr(kAXRoleAttribute as CFString)
        let subrole = attr(kAXSubroleAttribute as CFString)
        return (pid, role, subrole, isEditableAXRole(role: role, subrole: subrole))
    }

    private func isEditableAXRole(role: String, subrole: String) -> Bool {
        let explicitEditableRoles: Set<String> = [
            "AXTextArea",
            "AXTextField",
            "AXComboBox"
        ]

        if explicitEditableRoles.contains(role) { return true }
        if role.localizedCaseInsensitiveContains("Text") && role != "AXStaticText" { return true }
        if subrole.localizedCaseInsensitiveContains("Text") && subrole != "AXStaticText" { return true }
        return false
    }

    private func resolveDeferredIntraAppFocusChange(observedPID: pid_t) {
        let expectedPID = observedPID != 0 ? observedPID : activeFocusPID
        let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0
        let focusedState = focusedEditableElementState()
        let focusedAX = focusedElementAuditSummary()

        if frontmostPID == expectedPID,
           let focusedState,
           focusedState.pid == expectedPID,
           focusedState.isEditable {
            print("[InputCriticalSection] deferred AX focus change discarded after keyUp: same editable target focusedAX={\(focusedAX)}")
            return
        }

        print("[InputCriticalSection] deferred AX focus change applied after keyUp: real focus target changed frontmostPID=\(frontmostPID) expectedPID=\(expectedPID) focusedAX={\(focusedAX)}")
        if !CompletionManager.shared.isRewrite && !CompletionManager.shared.isSmartReply {
            CompletionManager.shared.cancelInflightTasks()
            CompletionManager.shared.hideOverlay()
            CompletionManager.shared.clearCompletion()
        }
        clearKeystrokeBuffer()
    }

    private func enqueueFocusAudit(label: String, type: CGEventType, event: CGEvent, delay: TimeInterval = 0) {
        guard InputIsolationMode.current.allowFocusAuditAXPolling else { return }
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        guard keyCode == 15 else { return }
        let eventType = eventTypeName(type)
        let timestamp = event.timestamp

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self else { return }
            let focusedPID = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0
            let focusedApp = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "unknown"
            let focusedAX = self.focusedElementAuditSummary()
            let overlay = CompletionManager.shared.overlayWindowController?.focusAuditSummary() ?? "overlayController=nil"
            let textInjectorRecent = InputIsolationMode.current.allowTextInjectorTapChecks
                ? TextInjector.shared.syntheticEventWithinLast(milliseconds: 500)
                : false
            print("[TypeFlow-InputAudit] focusSnapshot=\(label) eventType=\(eventType) keyCode=\(keyCode) timestamp=\(timestamp) focusedPID=\(focusedPID) focusedApp='\(self.escapedForInputAudit(focusedApp))' focusedAX={\(focusedAX)} overlay={\(overlay)} textInjectorWithin500ms=\(textInjectorRecent)")
        }
    }

    private func isOrdinaryPrintableKey(type: CGEventType, event: CGEvent, keyCode: Int64) -> Bool {
        guard type == .keyDown || type == .keyUp else { return false }
        if event.getIntegerValueField(.keyboardEventAutorepeat) != 0 { return false }

        let flags = event.flags
        if !flags.intersection([.maskCommand, .maskControl, .maskAlternate]).isEmpty {
            return false
        }

        let controlKeys: Set<Int64> = [36, 48, 51, 53, 76, 115, 116, 119, 121, 123, 124, 125, 126]
        if controlKeys.contains(keyCode) { return false }

        let characters = unicodeString(from: event)
        guard !characters.isEmpty else { return false }
        return characters.unicodeScalars.contains { scalar in
            !CharacterSet.controlCharacters.contains(scalar)
        }
    }

    private func hasPendingPrintableKeys() -> Bool {
        pendingNormalKeyLock.lock()
        let hasPending = !pendingPrintableKeys.isEmpty
        pendingNormalKeyLock.unlock()
        return hasPending
    }

    private func rememberPendingNormalKeyDown(keyCode: Int64, chars: String, event: CGEvent) {
        pendingNormalKeyLock.lock()
        pendingPrintableKeys[keyCode] = PendingPrintableKey(
            keyCode: keyCode,
            chars: chars,
            oldBuffer: keystrokeBuffer,
            event: event,
            keyDownTimestamp: event.timestamp
        )
        pendingNormalKeyLock.unlock()
    }

    private func pendingNormalKeyDown(keyCode: Int64) -> PendingPrintableKey? {
        pendingNormalKeyLock.lock()
        let pending = pendingPrintableKeys[keyCode]
        pendingNormalKeyLock.unlock()
        return pending
    }

    private func clearPendingNormalKeyDown(keyCode: Int64) {
        pendingNormalKeyLock.lock()
        pendingPrintableKeys.removeValue(forKey: keyCode)
        pendingNormalKeyLock.unlock()
    }

    private func reconcilePendingPrintableKey(_ pending: PendingPrintableKey) {
        let axSnapshot = getTextBeforeCaretSnapshot()
        let axAfterKeyUp = axSnapshot?.text ?? ""
        let oldBuffer = pending.oldBuffer
        let pendingChar = pending.chars
        let expectedBuffer = oldBuffer + pendingChar

        let sourceIsAuthoritative = axSnapshot?.source != .keystrokeBufferFallback && axSnapshot?.source != .none
        let axContainsPending = !axAfterKeyUp.isEmpty && (
            axAfterKeyUp.hasSuffix(expectedBuffer) ||
            axAfterKeyUp == expectedBuffer ||
            (axAfterKeyUp.hasSuffix(pendingChar) && axAfterKeyUp.count >= expectedBuffer.count)
        )

        let decision: String
        if sourceIsAuthoritative && axContainsPending {
            let canonicalSuffix = axAfterKeyUp.count > 150 ? String(axAfterKeyUp.suffix(150)) : axAfterKeyUp
            keystrokeBuffer = canonicalSuffix
            decision = "usedAXAlreadyContainsPending"
        } else if sourceIsAuthoritative && !axContainsPending {
            keystrokeBuffer = expectedBuffer.count > 150 ? String(expectedBuffer.suffix(150)) : expectedBuffer
            decision = "appendedPendingFallback"
            print("[InputBufferReconcile] pending key not reflected in AX; using provisional fallback")
        } else {
            keystrokeBuffer = expectedBuffer.count > 150 ? String(expectedBuffer.suffix(150)) : expectedBuffer
            decision = "deferredBecauseAXUncertain"
        }

        print("[InputBufferReconcile] oldBuffer='\(contextAuditPreview(oldBuffer))' pendingChar='\(contextAuditPreview(pendingChar))' axBeforeKeyUp='not-read-in-callback' axAfterKeyUp='\(contextAuditPreview(axAfterKeyUp))' decision=\(decision) newBuffer='\(contextAuditPreview(keystrokeBuffer))'")
        clearPendingNormalKeyDown(keyCode: pending.keyCode)
    }

    private func processObservedKeyDown(keyCode: Int64, event asyncEvent: CGEvent, skipPrintableAppend: Bool = false) {
        if keyCode == 51 || keyCode == 36 {
            print("[TypeFlow-Debug] Backspace/Return key detected: clearing and cancelling.")
            DispatchQueue.main.async {
                if !CompletionManager.shared.isRewrite && !CompletionManager.shared.isSmartReply {
                    CompletionManager.shared.clearCompletion()
                }
            }
        }

        // Check matchesPrefix first for all keys, including Space (keyCode 49) and Punctuation

        // Spacebar / Return Fast-Path
        if keyCode == 49 || keyCode == 36 {
            handleKeystroke(keyCode: keyCode, event: asyncEvent, skipPrintableAppend: skipPrintableAppend)
            let bufferSnapshot = keystrokeBuffer

            if keyCode == 49 {
                if let correctionData = CompletionManager.shared.handleAsynchronousSpellcheck(bufferSnapshot: bufferSnapshot) {
                    DispatchQueue.main.async {
                        let exactLength = correctionData.misspelledLength + 1
                        let delta = self.keystrokeBuffer.count - bufferSnapshot.count

                        guard delta >= 0 else { return }

                        let offsetFromEnd = exactLength + delta
                        if self.keystrokeBuffer.count >= offsetFromEnd {
                            let startIndex = self.keystrokeBuffer.index(self.keystrokeBuffer.endIndex, offsetBy: -offsetFromEnd)
                            let endIndex = self.keystrokeBuffer.index(startIndex, offsetBy: exactLength)
                            self.keystrokeBuffer.replaceSubrange(startIndex..<endIndex, with: correctionData.correction)
                        } else {
                            self.clearKeystrokeBuffer()
                        }
                    }
                }
            }

            triggerContextFetch(bufferSnapshot: bufferSnapshot, delay: 0.0)
            return
        }

        handleKeystroke(keyCode: keyCode, event: asyncEvent, skipPrintableAppend: skipPrintableAppend)
        let bufferSnapshot = keystrokeBuffer
        let isPunctuation = (keyCode == 43 || keyCode == 47)
        let delay = isPunctuation ? 0.0 : 0.15
        triggerContextFetch(bufferSnapshot: bufferSnapshot, delay: delay)
    }
    
    init(onCaretMoved: @escaping (CGRect) -> Void) {
        self.onCaretMoved = onCaretMoved
        
        NotificationCenter.default.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self else { return }
            if CompletionManager.shared.isRewrite { return }
            print("[TypeFlow-Debug] NSWorkspace.didActivateApplicationNotification triggered")
            
            if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
                if app.processIdentifier == NSRunningApplication.current.processIdentifier {
                    print("[TypeFlow-Debug] didActivateApplication: TypeFlow activated itself, ignoring focus clear")
                    return
                }
                if let rewritePID = CompletionManager.shared.activeRewritePID,
                   app.processIdentifier == rewritePID {
                    print("[TypeFlow-Debug] didActivateApplication: Original rewrite app activated, ignoring focus clear")
                    return
                }
                self.clearKeystrokeBuffer()
                CompletionManager.shared.clearCompletion()
                self.setupActiveAppObserver(for: app.processIdentifier)
            } else if let app = NSWorkspace.shared.frontmostApplication {
                if app.processIdentifier == NSRunningApplication.current.processIdentifier {
                    print("[TypeFlow-Debug] didActivateApplication: TypeFlow is frontmost, ignoring focus clear")
                    return
                }
                if let rewritePID = CompletionManager.shared.activeRewritePID,
                   app.processIdentifier == rewritePID {
                    print("[TypeFlow-Debug] didActivateApplication: Original rewrite app is frontmost, ignoring focus clear")
                    return
                }
                self.clearKeystrokeBuffer()
                CompletionManager.shared.clearCompletion()
                self.setupActiveAppObserver(for: app.processIdentifier)
            }
        }
        
        NotificationCenter.default.addObserver(
            forName: NSWorkspace.didDeactivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self else { return }
            if CompletionManager.shared.isRewrite { return }
            print("[TypeFlow-Debug] NSWorkspace.didDeactivateApplicationNotification triggered")
            
            if let frontmost = NSWorkspace.shared.frontmostApplication {
                if frontmost.processIdentifier == NSRunningApplication.current.processIdentifier {
                    print("[TypeFlow-Debug] didDeactivateApplication: TypeFlow is becoming frontmost, ignoring clear")
                    return
                }
                if let rewritePID = CompletionManager.shared.activeRewritePID,
                   frontmost.processIdentifier == rewritePID {
                    print("[TypeFlow-Debug] didDeactivateApplication: Original rewrite app is frontmost, ignoring clear")
                    return
                }
            }
            if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
                if app.processIdentifier == NSRunningApplication.current.processIdentifier {
                    print("[TypeFlow-Debug] didDeactivateApplication: TypeFlow itself deactivated, ignoring clear")
                    return
                }
                if let rewritePID = CompletionManager.shared.activeRewritePID,
                   app.processIdentifier == rewritePID {
                    print("[TypeFlow-Debug] didDeactivateApplication: Original rewrite app deactivated, ignoring clear")
                    return
                }
            }
            
            self.clearKeystrokeBuffer()
            CompletionManager.shared.clearCompletion()
            self.stopActiveAppObserver()
        }
    }
    
    private func setupActiveAppObserver(for pid: pid_t) {
        stopActiveAppObserver()
        activeFocusPID = pid
        
        var observer: AXObserver?
        let err = AXObserverCreate(pid, { (observer, element, notification, refcon) in
            // kAXFocusedUIElementChangedNotification fires repeatedly inside browsers
            // as the user types (e.g. URL bar losing focus, iframe gaining focus).
            // Only clear state when the *application PID* actually changes.
            guard let ref = refcon else { return }
            let unmanaged = Unmanaged<AccessibilityMonitor>.fromOpaque(ref)
            let obj = unmanaged.takeUnretainedValue()
            
            // Determine which PID owns the newly focused element
            var newPID: pid_t = 0
            AXUIElementGetPid(element, &newPID)
            
            if newPID != 0 && newPID != obj.activeFocusPID {
                if newPID == NSRunningApplication.current.processIdentifier {
                    print("[TypeFlow-Debug] AXObserver: focus moved to TypeFlow, ignoring buffer clear")
                    return
                }
                if CompletionManager.shared.isRewrite { return }
                // Real app switch — clear buffer and completions, then schedule focus-triggered generation
                print("[TypeFlow-Debug] AXObserver: focus moved to different PID (\(obj.activeFocusPID) -> \(newPID)), clearing buffer")
                obj.activeFocusPID = newPID
                DispatchQueue.main.async {
                    CompletionManager.shared.clearCompletion()
                    obj.clearKeystrokeBuffer()
                    // Schedule focus-triggered generation so ghost can appear in the new app
                    // without the user needing to type first.
                    obj.scheduleFocusTriggeredGeneration(reason: "interAppFocusChange", pid: newPID)
                }
            } else {
                // Intra-app focus jitter (same PID)
                if InputCriticalSection.shared.isActive {
                    print("[InputCriticalSection] AXObserver focus change deferred because physical key is down pid=\(newPID)")
                    InputCriticalSection.shared.runWhenSafe { [weak monitor = obj] in
                        DispatchQueue.main.async {
                            monitor?.resolveDeferredIntraAppFocusChange(observedPID: newPID)
                        }
                    }
                    return
                }

                if TextInjector.shared.syntheticEventWithinLast(milliseconds: 1500.0) {
                    print("[TypeFlow-Debug] AXObserver: intra-app focus change (PID \(newPID)) ignored because of recent synthetic injection")
                    return
                }
                print("[TypeFlow-Debug] AXObserver: intra-app focus change (PID \(newPID)), clearing overlay & buffer")
                DispatchQueue.main.async {
                    if !CompletionManager.shared.isRewrite && !CompletionManager.shared.isSmartReply {
                        CompletionManager.shared.cancelInflightTasks()
                        CompletionManager.shared.hideOverlay()
                        CompletionManager.shared.clearCompletion()
                        // Schedule focus-triggered generation after intra-app field change
                        obj.scheduleFocusTriggeredGeneration(reason: "intraAppFocusChange", pid: newPID)
                    }
                    obj.clearKeystrokeBuffer()
                }
            }
        }, &observer)
        
        if err == .success, let obs = observer {
            self.activeAppObserver = obs
            let runLoopSource = AXObserverGetRunLoopSource(obs)
            CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
            
            let appRef = AXUIElementCreateApplication(pid)
            let refcon = Unmanaged.passUnretained(self).toOpaque()
            let addErr = AXObserverAddNotification(obs, appRef, kAXFocusedUIElementChangedNotification as CFString, refcon)
            if addErr == .success {
                print("[TypeFlow-Debug] Successfully registered AXObserver for PID \(pid)")
            } else {
                print("[TypeFlow-Debug] Failed to register AXObserver notification: \(addErr.rawValue)")
            }
        } else {
            print("[TypeFlow-Debug] Failed to create AXObserver for PID \(pid): \(err.rawValue)")
        }
    }
    
    private func stopActiveAppObserver() {
        guard let obs = activeAppObserver else { return }
        let runLoopSource = AXObserverGetRunLoopSource(obs)
        CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        activeAppObserver = nil
        print("[TypeFlow-Debug] Stopped active app observer")
    }

    // Tracks the last context hash used for a focus-triggered generation, so we
    // don't spam the model if focus flickers on the same field.
    private var lastFocusTriggerContextHash: String = ""
    private var focusTriggerWorkItem: DispatchWorkItem?

    /// Schedule a low-priority generation triggered by a focus or caret change.
    /// Fires after `delayMs` ms (default 120ms). Skipped if:
    ///  - Model not ready / autocomplete disabled
    ///  - Active line is empty
    ///  - Same context hash as the last focus-triggered generation
    ///  - A visible ghost is already showing for this text
    ///  - Synthetic injection happened recently
    func scheduleFocusTriggeredGeneration(reason: String, pid: pid_t, delayMs: Int = 120) {
        // Cancel any previously scheduled focus-trigger
        focusTriggerWorkItem?.cancel()

        let item = DispatchWorkItem { [weak self] in
            guard let self = self else { return }

            // Guard: synthetic injection in flight
            if TextInjector.shared.syntheticEventWithinLast(milliseconds: 1500.0) {
                print("[FocusTrigger] skipped reason=syntheticInjectionRecent triggerReason=\(reason)")
                return
            }

            // Guard: autocomplete disabled
            guard SettingsManager.shared.enableAutocomplete else {
                print("[FocusTrigger] skipped reason=autocompleteDisabled triggerReason=\(reason)")
                return
            }

            // Guard: excluded app
            if let bundleId = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
               SettingsManager.shared.isAppExcluded(bundleId: bundleId) {
                print("[FocusTrigger] skipped reason=appExcluded bundleId=\(bundleId) triggerReason=\(reason)")
                return
            }

            // Fetch active text before caret
            let activeLine = self.getTextBeforeCaret() ?? ""
            let trimmed = activeLine.trimmingCharacters(in: .whitespacesAndNewlines)

            // Trigger background page context cache refresh on focus changes
            Task { [weak self] in
                guard let self = self else { return }
                await ScreenContextManager.shared.refreshScreenContextCache(accessibilityMonitor: self)
            }


            // Guard: no useful text
            guard !trimmed.isEmpty else {
                print("[FocusTrigger] skipped reason=emptyLine triggerReason=\(reason)")
                return
            }

            // Compute a lightweight context hash (FNV-1a on last 200 chars)
            let sample = String(activeLine.suffix(200))
            var contextHash: UInt64 = 14_695_981_039_346_656_037
            for byte in sample.utf8 {
                contextHash ^= UInt64(byte)
                contextHash &*= 1_099_511_628_211
            }
            let hashStr = String(format: "%016llx", contextHash)

            // Guard: same context as last focus-trigger (field didn't change)
            if hashStr == self.lastFocusTriggerContextHash {
                print("[FocusTrigger] skipped reason=sameContextHash contextHash=\(hashStr) triggerReason=\(reason)")
                return
            }

            // Guard: visible ghost already current for this text
            if let ghost = CompletionManager.shared.displayedCompletion, !ghost.isEmpty {
                let expectedLine = activeLine  // ghost is shown for this text
                let currentLine = self.getTextBeforeCaret() ?? ""
                if currentLine == expectedLine {
                    print("[FocusTrigger] skipped reason=ghostAlreadyVisible triggerReason=\(reason)")
                    return
                }
            }

            self.lastFocusTriggerContextHash = hashStr
            print("[FocusTrigger] scheduling generation triggerReason=\(reason) pid=\(pid) contextHash=\(hashStr) activeLineLen=\(activeLine.count)")

            DispatchQueue.main.async {
                let diag: [String: Any] = [
                    "epochSeconds": Date().timeIntervalSince1970,
                    "focusRefreshScheduled": true,
                    "triggerReason": reason,
                    "contextHash": hashStr,
                    "activeLineLen": activeLine.count
                ]
                if let data = try? JSONSerialization.data(withJSONObject: diag),
                   let str = String(data: data, encoding: .utf8) {
                    print("[FocusTriggerDiagnostic] \(str)")
                    fflush(stdout)
                }
                CompletionManager.shared.onTextChanged(bufferFallback: activeLine)
            }
        }

        focusTriggerWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(delayMs), execute: item)
    }
    
    /// Called once at launch (after 1-second delay). Retries every 2 seconds
    /// until the CGEvent tap is successfully created.
    ///
    /// WHY: AXIsProcessTrusted() is unreliable — it can return false after a
    /// fresh build even when permission IS granted in System Settings (the binary
    /// path changed so macOS revoked the cached trust). CGEvent.tapCreate is the
    /// definitive OS-level permission check: if it returns non-nil, we're trusted.
    func startWithRetry() {
        guard !isRunning else { return }

        if InputIsolationMode.current == .modeA {
            start()
            if isRunning {
                print("[TypeFlow] Accessibility monitor diagnostic no-tap mode started successfully.")
            }
            return
        }
        
        let isAlreadyTrusted = AXIsProcessTrusted()
        if isAlreadyTrusted {
            print("[TypeFlow] Accessibility is already trusted. Attempting to start event tap...")
            start()
            if isRunning {
                print("[TypeFlow] Accessibility monitor started successfully.")
                return
            }
            
            print("[TypeFlow] Event tap creation failed despite trust status. Starting retry loop without prompt...")
            retryTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] timer in
                guard let self = self else { timer.invalidate(); return }
                self.start()
                if self.isRunning {
                    print("[TypeFlow] Accessibility monitor started successfully after retry.")
                    timer.invalidate()
                    self.retryTimer = nil
                }
            }
            return
        }
        
        // Tap creation failed / not trusted = permission actually denied.
        // Show the system prompt once, then poll every 2 seconds.
        print("[TypeFlow] Accessibility permission required. Showing system prompt...")
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        AXIsProcessTrustedWithOptions(options as CFDictionary)
        
        retryTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] timer in
            guard let self = self else { timer.invalidate(); return }
            self.start()
            if self.isRunning {
                print("[TypeFlow] Accessibility monitor started after permission grant.")
                timer.invalidate()
                self.retryTimer = nil
            }
        }
    }
    
    private var diagnosticNoTapModeRunning = false
    private var isRunning: Bool { diagnosticNoTapModeRunning || observerTap != nil || acceptTap != nil }
    var consumedKeyCodes: Set<Int64> = []
    var isExpandingAbbreviation = false

    func setAcceptTapNeededForVisibleCompletion(_ needed: Bool, reason: String) {
        guard InputIsolationMode.current.allowDynamicAcceptTap else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if needed {
                self.installDynamicAcceptTapIfNeeded(reason: reason)
            } else {
                self.disableDynamicAcceptTapIfNeeded(reason: reason)
            }
        }
    }

    private func installDynamicAcceptTapIfNeeded(reason: String) {
        guard acceptTap == nil else { return }

        let installStartedAt = CFAbsoluteTimeGetCurrent()
        let eventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
        acceptTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .tailAppendEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                return autoreleasepool {
                    let callbackStart = CFAbsoluteTimeGetCurrent()

                    if TextInjector.shared.isInjecting || event.getIntegerValueField(.eventSourceUserData) == 9999 {
                        return Unmanaged.passUnretained(event)
                    }

                    guard let monitor = refcon else { return Unmanaged.passUnretained(event) }
                    let obj = Unmanaged<AccessibilityMonitor>.fromOpaque(monitor).takeUnretainedValue()
                    let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
                    let currentCompletionNonEmpty = CompletionManager.shared.displayedCompletion?.isEmpty == false
                    let hasVisibleCompletion = currentCompletionNonEmpty && CompletionManager.shared.isOverlayVisible

                    if type == .keyUp, obj.consumedKeyCodes.contains(keyCode) {
                        obj.consumedKeyCodes.remove(keyCode)
                        obj.enqueueInputAudit(tap: "accept", type: type, event: event, action: "dynamic-accept-consumed-keyUp-swallowed", matchedShortcut: true, originalReturned: false, callbackStart: callbackStart, completionActive: currentCompletionNonEmpty, overlayVisible: CompletionManager.shared.isOverlayVisible, currentCompletionNonEmpty: currentCompletionNonEmpty)
                        if obj.consumedKeyCodes.isEmpty, let pendingReason = obj.pendingDisableReason {
                            obj.pendingDisableReason = nil
                            DispatchQueue.main.async {
                                obj.disableDynamicAcceptTapIfNeeded(reason: pendingReason)
                            }
                        }
                        return nil
                    }

                    guard hasVisibleCompletion else {
                        obj.setAcceptTapNeededForVisibleCompletion(false, reason: "dynamic-no-visible-completion")
                        obj.enqueueInputAudit(tap: "accept", type: type, event: event, action: "dynamic-no-completion-passThrough", matchedShortcut: false, originalReturned: true, callbackStart: callbackStart, completionActive: currentCompletionNonEmpty, overlayVisible: CompletionManager.shared.isOverlayVisible, currentCompletionNonEmpty: currentCompletionNonEmpty)
                        return Unmanaged.passUnretained(event)
                    }

                    if type == .keyDown && keyCode == 48 {
                        if CompletionManager.shared.handleTabPressed() {
                            obj.clearKeystrokeBuffer()
                            obj.consumedKeyCodes.insert(keyCode)
                            obj.enqueueInputAudit(tap: "accept", type: type, event: event, action: "dynamic-tab-visible-completion-swallowed", matchedShortcut: true, originalReturned: false, callbackStart: callbackStart, completionActive: currentCompletionNonEmpty, overlayVisible: CompletionManager.shared.isOverlayVisible, currentCompletionNonEmpty: currentCompletionNonEmpty)
                            return nil
                        }
                    }

                    obj.enqueueInputAudit(tap: "accept", type: type, event: event, action: "dynamic-inspected-passThrough", matchedShortcut: false, originalReturned: true, callbackStart: callbackStart, completionActive: currentCompletionNonEmpty, overlayVisible: CompletionManager.shared.isOverlayVisible, currentCompletionNonEmpty: currentCompletionNonEmpty)
                    return Unmanaged.passUnretained(event)
                }
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )

        guard let tap = acceptTap else {
            let installMs = (CFAbsoluteTimeGetCurrent() - installStartedAt) * 1000.0
            print("[RenderSchedule] acceptTapInstallMs=\(String(format: "%.1f", installMs)) success=false")
            print("[TypeFlow-InputAudit] acceptTap=dynamicCreateFailed enabled=false reason=\(reason)")
            return
        }

        acceptRunLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), acceptRunLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        let installMs = (CFAbsoluteTimeGetCurrent() - installStartedAt) * 1000.0
        print("[RenderSchedule] acceptTapInstallMs=\(String(format: "%.1f", installMs)) success=true reason=\(reason)")
        print("[TypeFlow-InputAudit] acceptTap=dynamicCreated enabled=true location=cgSessionEventTap place=tailAppendEventTap options=defaultTap reason=\(reason)")
    }

    private func disableDynamicAcceptTapIfNeeded(reason: String) {
        guard InputIsolationMode.current.allowDynamicAcceptTap, let tap = acceptTap else { return }
        if !consumedKeyCodes.isEmpty {
            pendingDisableReason = reason
            print("[TypeFlow-InputAudit] acceptTap=disableDeferred reason=\(reason) consumedKeyCodes=\(consumedKeyCodes)")
            return
        }
        CGEvent.tapEnable(tap: tap, enable: false)
        if let source = acceptRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        acceptTap = nil
        acceptRunLoopSource = nil
        print("[TypeFlow-InputAudit] acceptTap=dynamicDisabled enabled=false reason=\(reason)")
    }
    
    func start() {
        let inputMode = InputIsolationMode.current
        print("[TypeFlow-InputIsolation] start \(inputMode.summary)")

        if inputMode == .modeA {
            diagnosticNoTapModeRunning = true
            print("[TypeFlow-InputIsolation] Mode A active: no CGEvent taps installed; observerEnabled=false acceptEnabled=false axObserverAllowed=false overlayAllowed=false generationAllowed=false")
            return
        }

        // Prewarm singletons that are consulted by the tap callbacks. A lazy
        // init on the first physical key can delay the original key event just
        // enough for macOS's press-and-hold accent detector to misclassify it.
        if inputMode.prewarmTextInjector {
            _ = TextInjector.shared
        } else {
            print("[TypeFlow-InputIsolation] TextInjector prewarm disabled mode=\(inputMode.label)")
        }

        let eventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue) | (1 << CGEventType.leftMouseDown.rawValue) | (1 << CGEventType.rightMouseDown.rawValue)
        
        // 1. OBSERVER TAP (listenOnly): Tracks all keys asynchronously without blocking the system.
        // Uses .cgSessionEventTap (not .cghidEventTap) to stay within the session-level event chain.
        // A .cghidEventTap at .headInsertEventTap runs before macOS's long-press detector, so even
        // a listenOnly tap there creates enough timing jitter to trigger the accent menu on 'R'.
        // .cgSessionEventTap runs AFTER the HID server has already committed the long-press timeout,
        // so listenOnly-at-session-head is safe for the keyboard at any typing speed.
        if inputMode.installObserverTap {
            observerTap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .listenOnly,
                eventsOfInterest: CGEventMask(eventMask),
                callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                return autoreleasepool {
                    let callbackStart = CFAbsoluteTimeGetCurrent()
                    let diagnosticMode = InputIsolationMode.current


                if diagnosticMode.allowTextInjectorTapChecks {
                    if TextInjector.shared.isInjecting || event.getIntegerValueField(.eventSourceUserData) == 9999 {
                        return Unmanaged.passUnretained(event)
                    }
                } else if event.getIntegerValueField(.eventSourceUserData) == 9999 {
                    return Unmanaged.passUnretained(event)
                }
                
                let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
                
                if let monitor = refcon {
                    let unmanaged = Unmanaged<AccessibilityMonitor>.fromOpaque(monitor)
                    let obj = unmanaged.takeUnretainedValue()

                    if diagnosticMode.observerTapPassThroughOnly {
                        obj.enqueueInputAudit(tap: "observer", type: type, event: event, action: "diagnostic-observer-passThrough", matchedShortcut: false, originalReturned: true, callbackStart: callbackStart, completionActive: false, overlayVisible: false, currentCompletionNonEmpty: false)
                        if diagnosticMode.allowFocusAuditAXPolling {
                            obj.enqueueFocusAudit(label: "diagnostic-observer-ax-poll", type: type, event: event)
                        }
                        return Unmanaged.passUnretained(event)
                    }
                    
                    if type == .keyDown && keyCode == 48 && CompletionManager.shared.isOverlayVisible {
                        return Unmanaged.passUnretained(event)
                    }
                    
                    // Mouse clicks reset state
                    if type == .leftMouseDown || type == .rightMouseDown {
                        DispatchQueue.main.async {
                            if !CompletionManager.shared.isRewrite && !CompletionManager.shared.isSmartReply {
                                CompletionManager.shared.cancelInflightTasks()
                                CompletionManager.shared.hideOverlay()
                                CompletionManager.shared.clearCompletion()
                            }
                            obj.clearKeystrokeBuffer()
                        }
                        return Unmanaged.passUnretained(event)
                    }
                    
                    if type == .keyDown {
                        // Suppressed: print("[TypeFlow] Observer keyDown detected: keyCode=\(keyCode)")

                        // Pass event processing to the background immediately.
                        // The tap callback MUST return without blocking — copy the event
                        // and hand it off to the dedicated serial tapQueue so the CGEvent
                        // tap thread is never waiting on locks, AX IPC, or LLM state.
                        guard let asyncEvent = event.copy() else {
                            let currentCompletionNonEmpty = CompletionManager.shared.displayedCompletion?.isEmpty == false
                            obj.enqueueInputAudit(tap: "observer", type: type, event: event, action: "observed-copy-failed-passThrough", matchedShortcut: false, originalReturned: true, callbackStart: callbackStart, completionActive: currentCompletionNonEmpty, overlayVisible: CompletionManager.shared.isOverlayVisible, currentCompletionNonEmpty: currentCompletionNonEmpty)
                            return Unmanaged.passUnretained(event)
                        }

                        if obj.isOrdinaryPrintableKey(type: type, event: event, keyCode: keyCode) {
                            let chars = obj.unicodeString(from: event)
                            InputCriticalSection.shared.begin(keyCode: keyCode, chars: chars)
                            obj.rememberPendingNormalKeyDown(keyCode: keyCode, chars: chars, event: asyncEvent)
                            let currentCompletionNonEmpty = CompletionManager.shared.displayedCompletion?.isEmpty == false
                            obj.enqueueInputAudit(tap: "observer", type: type, event: event, action: "observed-deferredUntilKeyUp-passThrough", matchedShortcut: false, originalReturned: true, callbackStart: callbackStart, completionActive: currentCompletionNonEmpty, overlayVisible: CompletionManager.shared.isOverlayVisible, currentCompletionNonEmpty: currentCompletionNonEmpty)
                            obj.enqueueFocusAudit(label: "keyDown-postReturn-beforeTypeFlowWork", type: type, event: event)
                            return Unmanaged.passUnretained(event)
                        }

                        obj.tapQueue.async {
                            obj.processObservedKeyDown(keyCode: keyCode, event: asyncEvent)
                        }
                        let currentCompletionNonEmpty = CompletionManager.shared.displayedCompletion?.isEmpty == false
                        obj.enqueueInputAudit(tap: "observer", type: type, event: event, action: "observed-queued-passThrough", matchedShortcut: false, originalReturned: true, callbackStart: callbackStart, completionActive: currentCompletionNonEmpty, overlayVisible: CompletionManager.shared.isOverlayVisible, currentCompletionNonEmpty: currentCompletionNonEmpty)
                    } else if type == .keyUp {
                        if let pendingKeyDown = obj.pendingNormalKeyDown(keyCode: keyCode) {
                            InputCriticalSection.shared.end(keyCode: keyCode, chars: obj.unicodeString(from: event))
                            obj.tapQueue.async {
                                obj.reconcilePendingPrintableKey(pendingKeyDown)
                                obj.processObservedKeyDown(keyCode: keyCode, event: pendingKeyDown.event, skipPrintableAppend: true)
                            }
                        }
                        let currentCompletionNonEmpty = CompletionManager.shared.displayedCompletion?.isEmpty == false
                        obj.enqueueInputAudit(tap: "observer", type: type, event: event, action: "observed-keyUp-passThrough", matchedShortcut: false, originalReturned: true, callbackStart: callbackStart, completionActive: currentCompletionNonEmpty, overlayVisible: CompletionManager.shared.isOverlayVisible, currentCompletionNonEmpty: currentCompletionNonEmpty)
                        obj.enqueueFocusAudit(label: "keyUp-postReturn-afterTypeFlowWorkQueued", type: type, event: event)
                        obj.enqueueFocusAudit(label: "keyUp-postReturn-plus100ms", type: type, event: event, delay: 0.1)
                    }
                }
                
                return Unmanaged.passUnretained(event)
                }
                },
                userInfo: Unmanaged.passUnretained(self).toOpaque()
            )
        } else {
            observerTap = nil
            print("[TypeFlow-InputIsolation] observerTap not installed mode=\(inputMode.label)")
        }
        
        // 2. ACCEPT TAP (defaultTap): Tightly scoped tap to consume acceptance keys and shortcuts.
        // Tail-appended so it runs AFTER the listenOnly observer has already classified the event.
        // Using .tailAppendEventTap means all other apps see the event first; we only intervene
        // when CompletionManager has a visible completion or a rewrite/smart-reply is active.
        // This is identical to Cotabby's InputMonitor two-tap architecture (PR #328 invariant).
        if inputMode.installAcceptTapAtLaunch {
            acceptTap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .tailAppendEventTap,
                options: .defaultTap,
                eventsOfInterest: CGEventMask(eventMask),
                callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                return autoreleasepool {
                    let callbackStart = CFAbsoluteTimeGetCurrent()
                let diagnosticMode = InputIsolationMode.current
                if diagnosticMode.acceptTapPassThroughOnly {
                    if let monitor = refcon {
                        let unmanaged = Unmanaged<AccessibilityMonitor>.fromOpaque(monitor)
                        let obj = unmanaged.takeUnretainedValue()
                        obj.enqueueInputAudit(tap: "accept", type: type, event: event, action: "diagnostic-accept-noop-passThrough", matchedShortcut: false, originalReturned: true, callbackStart: callbackStart, completionActive: false, overlayVisible: false, currentCompletionNonEmpty: false)
                    }
                    return Unmanaged.passUnretained(event)
                }

                if diagnosticMode.allowTextInjectorTapChecks {
                    if TextInjector.shared.isInjecting || event.getIntegerValueField(.eventSourceUserData) == 9999 {
                        return Unmanaged.passUnretained(event)
                    }
                } else if event.getIntegerValueField(.eventSourceUserData) == 9999 {
                    return Unmanaged.passUnretained(event)
                }
                
                let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
                let flags = event.flags
                
                var isAbbreviationTrigger = false
                var monitorObj: AccessibilityMonitor?
                if let monitor = refcon {
                    let unmanaged = Unmanaged<AccessibilityMonitor>.fromOpaque(monitor)
                    let obj = unmanaged.takeUnretainedValue()
                    monitorObj = obj
                    if type == .keyDown {
                        if obj.isExpandingAbbreviation {
                            isAbbreviationTrigger = true
                            obj.isExpandingAbbreviation = false
                        }
                    }
                }
                
                let isKeyEvent = type == .keyDown || type == .keyUp
                let hasShortcutModifier = !flags.intersection([.maskCommand, .maskControl, .maskAlternate]).isEmpty
                let isTypeFlowControlKey = keyCode == 53 || keyCode == 48 || keyCode == 124
                let wasPreviouslyConsumed = monitorObj?.consumedKeyCodes.contains(keyCode) ?? false
                let shouldInspectForTypeFlowHandling = isKeyEvent && (isTypeFlowControlKey || hasShortcutModifier || isAbbreviationTrigger || wasPreviouslyConsumed)

                // Fast path bypass for ordinary typing. This must apply even while
                // a completion is active: normal character keys are observed by the
                // listen-only tap, never processed by the swallowing/default tap.
                if isKeyEvent && !shouldInspectForTypeFlowHandling {
                    let currentCompletionNonEmpty = CompletionManager.shared.displayedCompletion?.isEmpty == false
                    monitorObj?.enqueueInputAudit(tap: "accept", type: type, event: event, action: "normal-key-passThrough", matchedShortcut: false, originalReturned: true, callbackStart: callbackStart, completionActive: currentCompletionNonEmpty, overlayVisible: CompletionManager.shared.isOverlayVisible, currentCompletionNonEmpty: currentCompletionNonEmpty)
                    monitorObj?.enqueueFocusAudit(label: "accept-postReturn", type: type, event: event)
                    return Unmanaged.passUnretained(event)
                }

                let hasCompletion = CompletionManager.shared.displayedCompletion?.isEmpty == false
                let isRewriteActive = CompletionManager.shared.isRewrite
                let isSmartReplyActive = CompletionManager.shared.isSmartReply
                
                if let obj = monitorObj {
                    
                    if type == .keyDown || type == .keyUp {
                        // Only evaluate shortcut matches when at least one modifier key is
                        // held. A bare alphanumeric keypress (e.g. plain 'r') must NEVER
                        // be swallowed here regardless of the configured shortcut string.
                        let hasAnyModifier = !flags.intersection([.maskCommand, .maskControl, .maskAlternate]).isEmpty
                        
                        if hasAnyModifier {
                            // Rewrite Shortcut
                            if obj.matchesRewriteShortcut(event: event) {
                                if type == .keyDown {
                                    print("[TypeFlow] Intercepted Rewrite Shortcut (keyDown)")
                                    DispatchQueue.main.async { CompletionManager.shared.triggerRewrite() }
                                }
                                obj.enqueueInputAudit(tap: "accept", type: type, event: event, action: "rewrite-shortcut-swallowed", matchedShortcut: true, originalReturned: false, callbackStart: callbackStart, completionActive: hasCompletion, overlayVisible: CompletionManager.shared.isOverlayVisible, currentCompletionNonEmpty: hasCompletion)
                                return nil
                            }
                            
                            // Smart Reply Shortcut
                            if obj.matchesSmartReplyShortcut(event: event) {
                                if type == .keyDown {
                                    print("[TypeFlow] Intercepted Smart Reply Shortcut (keyDown)")
                                    DispatchQueue.main.async { CompletionManager.shared.triggerSmartReply() }
                                }
                                obj.enqueueInputAudit(tap: "accept", type: type, event: event, action: "smart-reply-shortcut-swallowed", matchedShortcut: true, originalReturned: false, callbackStart: callbackStart, completionActive: hasCompletion, overlayVisible: CompletionManager.shared.isOverlayVisible, currentCompletionNonEmpty: hasCompletion)
                                return nil
                            }
                        }
                    }
                    
                    if type == .keyDown {
                        // Abbreviation trigger: only swallow the actual delimiter keyCodes
                        // (Space=49, Tab=48, Comma=43, Period=47). Any other keyCode means
                        // the flag was set erroneously — clear it and let the event through.
                        let isDelimiterKey = keyCode == 49 || keyCode == 48 || keyCode == 43 || keyCode == 47
                        if isAbbreviationTrigger && isDelimiterKey {
                            obj.consumedKeyCodes.insert(keyCode)
                            obj.enqueueInputAudit(tap: "accept", type: type, event: event, action: "abbreviation-delimiter-swallowed", matchedShortcut: false, originalReturned: false, callbackStart: callbackStart, completionActive: hasCompletion, overlayVisible: CompletionManager.shared.isOverlayVisible, currentCompletionNonEmpty: hasCompletion)
                            return nil
                        } else if isAbbreviationTrigger {
                            // Stale flag from a race — clear it and fall through
                            obj.isExpandingAbbreviation = false
                        }
                        
                        if keyCode == 53 { // Escape
                            if isRewriteActive || isSmartReplyActive {
                                obj.consumedKeyCodes.removeAll() // clear any stale consumed keyCodes
                                DispatchQueue.main.async { CompletionManager.shared.clearCompletion() }
                                obj.enqueueInputAudit(tap: "accept", type: type, event: event, action: "escape-rewrite-smartReply-swallowed", matchedShortcut: true, originalReturned: false, callbackStart: callbackStart, completionActive: hasCompletion, overlayVisible: CompletionManager.shared.isOverlayVisible, currentCompletionNonEmpty: hasCompletion)
                                return nil
                            }
                        }
                        
                        if keyCode == 48 && CompletionManager.shared.isOverlayVisible && hasCompletion {
                            _ = CompletionManager.shared.handleTabPressed()
                            obj.clearKeystrokeBuffer()
                            obj.consumedKeyCodes.insert(keyCode)
                            obj.enqueueInputAudit(tap: "accept", type: type, event: event, action: "tab-visible-completion-swallowed", matchedShortcut: true, originalReturned: false, callbackStart: callbackStart, completionActive: hasCompletion, overlayVisible: CompletionManager.shared.isOverlayVisible, currentCompletionNonEmpty: hasCompletion)
                            return nil
                        }
                        
                        var shortcutConsumed = false
                        if (keyCode == 48 && (SettingsManager.shared.acceptShortcut == "Tab" || isRewriteActive)) ||
                           (keyCode == 124 && SettingsManager.shared.acceptShortcut == "Right Arrow") {
                            // Only intercept if there is a real completion visible
                            if hasCompletion || isRewriteActive {
                                if CompletionManager.shared.handleTabPressed() {
                                    shortcutConsumed = true
                                }
                            }
                        }
                        
                        if shortcutConsumed {
                            obj.clearKeystrokeBuffer()
                            obj.consumedKeyCodes.insert(keyCode)
                            obj.enqueueInputAudit(tap: "accept", type: type, event: event, action: "accept-shortcut-swallowed", matchedShortcut: true, originalReturned: false, callbackStart: callbackStart, completionActive: hasCompletion, overlayVisible: CompletionManager.shared.isOverlayVisible, currentCompletionNonEmpty: hasCompletion)
                            return nil
                        }
                        
                        // During rewrite/smart-reply ONLY swallow the specific acceptance/
                        // shortcut keys (Tab=48, Right Arrow=124, Escape=53) — NOT normal
                        // alphanumeric typing, which must reach the host application.
                        let isAcceptanceKey = keyCode == 48 || keyCode == 124 || keyCode == 53
                        if (isRewriteActive || isSmartReplyActive) && isAcceptanceKey {
                            obj.consumedKeyCodes.insert(keyCode)
                            obj.enqueueInputAudit(tap: "accept", type: type, event: event, action: "rewrite-smartReply-control-key-swallowed", matchedShortcut: true, originalReturned: false, callbackStart: callbackStart, completionActive: hasCompletion, overlayVisible: CompletionManager.shared.isOverlayVisible, currentCompletionNonEmpty: hasCompletion)
                            return nil
                        }
                    } else if type == .keyUp {
                        if obj.consumedKeyCodes.contains(keyCode) {
                            obj.consumedKeyCodes.remove(keyCode)
                            obj.enqueueInputAudit(tap: "accept", type: type, event: event, action: "consumed-keyUp-swallowed", matchedShortcut: true, originalReturned: false, callbackStart: callbackStart, completionActive: hasCompletion, overlayVisible: CompletionManager.shared.isOverlayVisible, currentCompletionNonEmpty: hasCompletion)
                            return nil
                        }
                    }

                    obj.enqueueInputAudit(tap: "accept", type: type, event: event, action: "inspected-passThrough", matchedShortcut: false, originalReturned: true, callbackStart: callbackStart, completionActive: hasCompletion, overlayVisible: CompletionManager.shared.isOverlayVisible, currentCompletionNonEmpty: hasCompletion)
                }
                
                return Unmanaged.passUnretained(event)
                }
                },
                userInfo: Unmanaged.passUnretained(self).toOpaque()
            )
        } else {
            acceptTap = nil
            let reason = inputMode.allowDynamicAcceptTap ? "disabled-until-visible-non-empty-completion" : "mode-disabled"
            print("[TypeFlow-InputIsolation] acceptTap not installed at launch mode=\(inputMode.label) reason=\(reason)")
        }
        
        // Add BOTH taps to the run loop
        if let obsTap = observerTap {
            observerRunLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, obsTap, 0)
            CFRunLoopAddSource(CFRunLoopGetMain(), observerRunLoopSource, .commonModes)
            CGEvent.tapEnable(tap: obsTap, enable: true)
            print("[TypeFlow-InputAudit] observerTap=created enabled=true location=cgSessionEventTap place=headInsertEventTap options=listenOnly mode=\(inputMode.label)")
        } else {
            print("[TypeFlow-InputAudit] observerTap=notInstalledOrFailed enabled=false mode=\(inputMode.label)")
        }
        
        if let accTap = acceptTap {
            acceptRunLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, accTap, 0)
            CFRunLoopAddSource(CFRunLoopGetMain(), acceptRunLoopSource, .commonModes)
            CGEvent.tapEnable(tap: accTap, enable: true)
            print("[TypeFlow-InputAudit] acceptTap=created enabled=true location=cgSessionEventTap place=tailAppendEventTap options=defaultTap passThroughOnly=\(inputMode.acceptTapPassThroughOnly) mode=\(inputMode.label)")
        } else {
            print("[TypeFlow-InputAudit] acceptTap=notInstalledOrFailed enabled=false mode=\(inputMode.label)")
        }
        
        if inputMode.allowAXObserver, let app = NSWorkspace.shared.frontmostApplication {
            self.setupActiveAppObserver(for: app.processIdentifier)
        } else {
            print("[TypeFlow-InputIsolation] AXObserver setup skipped mode=\(inputMode.label) allowed=\(inputMode.allowAXObserver)")
        }
    }
    
    private func triggerContextFetch(bufferSnapshot: String, delay: TimeInterval) {
        guard InputIsolationMode.current.allowGeneration else {
            print("[TypeFlow-InputIsolation] generation skipped mode=\(InputIsolationMode.current.label) triggerContextFetch bufferLen=\(bufferSnapshot.count)")
            return
        }

        let currentPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let currentTitle = self.getActiveWindowTitle()

        let contextStale = ScreenContextManager.shared.cachedContext == nil ||
            Date().timeIntervalSince(ScreenContextManager.shared.cachedContext!.timestamp) > 30.0 ||
            currentPID != ScreenContextManager.lastPID ||
            currentTitle != ScreenContextManager.lastWindowTitle

        if contextStale {
            ScreenContextManager.lastPID = currentPID
            ScreenContextManager.lastWindowTitle = currentTitle
        }

        let inputTime = LatencyInstrumentation.shared.recordInputEvent(bufferLen: bufferSnapshot.count, delay: 0)
        print("[DebounceAudit] no AccessibilityMonitor debounce before CompletionManager debounce")
        if delay > 0 {
            print("[DebounceAudit] AccessibilityMonitor delay bypassed oldDelayMs=\(Int(delay * 1000))")
        }
        contextFetchWorkItem?.cancel()

        let needsInlineRefresh = contextStale
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            LatencyInstrumentation.shared.contextFetchStart(inputTime: inputTime, bufferLen: bufferSnapshot.count)

            // No synchronous inline refresh in the typing hot path to prevent input latency.
            // Asynchronously dispatch cache refresh in the background.
            if needsInlineRefresh && !ScreenContextManager.testingMode {
                Task { [weak self] in
                    guard let self = self else { return }
                    await ScreenContextManager.shared.refreshScreenContextCache(accessibilityMonitor: self)
                }
            }
            print("[ScreenContextDiagnostic] contextRefreshInHotPath=false extractionBlockedTypingMs=0.0")


            // NOTE: Caret rect is intentionally NOT fetched here.
            // getCurrentCaretRect() is a heavy AX IPC call. Executing it on every
            // keystroke was causing "Significant Energy" warnings and AXTextMarker spam.
            // Caret position is now only fetched once, immediately before showing the overlay.
            DispatchQueue.main.async {
                CompletionManager.shared.onTextChanged(bufferFallback: bufferSnapshot)
                LatencyInstrumentation.shared.contextFetchEnd(bufferLen: bufferSnapshot.count)
            }
        }

        contextFetchWorkItem = workItem

        processingQueue.async(execute: workItem)
    }
    
    func stop() {
        if let tap = observerTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let source = observerRunLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            }
            observerTap = nil
            observerRunLoopSource = nil
        }
        
        if let tap = acceptTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let source = acceptRunLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            }
            acceptTap = nil
            acceptRunLoopSource = nil
        }
        
        stopActiveAppObserver()
        print("[TypeFlow] Accessibility monitor stopped.")
    }
    
    func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        AXIsProcessTrustedWithOptions(options as CFDictionary)
    }
    
    private func geometryProbeID(_ requestID: UInt64?) -> String {
        requestID.map(String.init) ?? "nil"
    }

    private func geometryProbeRect(_ rect: CGRect?) -> String {
        guard let rect else { return "nil" }
        return String(
            format: "{{x=%.1f,y=%.1f,w=%.1f,h=%.1f}}",
            rect.origin.x,
            rect.origin.y,
            rect.width,
            rect.height
        )
    }

    private func geometryProbeError(_ error: AXError) -> String {
        switch error {
        case .success: return "success"
        case .failure: return "failure"
        case .illegalArgument: return "illegalArgument"
        case .invalidUIElement: return "invalidUIElement"
        case .invalidUIElementObserver: return "invalidUIElementObserver"
        case .cannotComplete: return "cannotComplete"
        case .attributeUnsupported: return "attributeUnsupported"
        case .actionUnsupported: return "actionUnsupported"
        case .notificationUnsupported: return "notificationUnsupported"
        case .notImplemented: return "notImplemented"
        case .notificationAlreadyRegistered: return "notificationAlreadyRegistered"
        case .notificationNotRegistered: return "notificationNotRegistered"
        case .apiDisabled: return "apiDisabled"
        case .noValue: return "noValue"
        case .parameterizedAttributeUnsupported: return "parameterizedAttributeUnsupported"
        case .notEnoughPrecision: return "notEnoughPrecision"
        @unknown default: return "unknown(\(error.rawValue))"
        }
    }

    private func geometryProbeAXRect(_ value: CFTypeRef?) -> CGRect? {
        guard let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let axValue = value as! AXValue
        var rect = CGRect.zero
        guard AXValueGetValue(axValue, .cgRect, &rect) else { return nil }
        return rect
    }

    private func geometryProbeAXPoint(_ value: CFTypeRef?) -> CGPoint? {
        guard let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let axValue = value as! AXValue
        var point = CGPoint.zero
        guard AXValueGetValue(axValue, .cgPoint, &point) else { return nil }
        return point
    }

    private func geometryProbeAXSize(_ value: CFTypeRef?) -> CGSize? {
        guard let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let axValue = value as! AXValue
        var size = CGSize.zero
        guard AXValueGetValue(axValue, .cgSize, &size) else { return nil }
        return size
    }

    private func geometryProbeAttributeString(_ axElement: AXUIElement, attribute: CFString) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axElement, attribute, &value) == .success,
              let string = value as? String else {
            return nil
        }
        return string
    }

    private func editableElementPID(_ axElement: AXUIElement) -> pid_t {
        var pid: pid_t = 0
        AXUIElementGetPid(axElement, &pid)
        return pid
    }

    private func editableElementRoleInfo(_ axElement: AXUIElement) -> (role: String, subrole: String) {
        let role = geometryProbeAttributeString(axElement, attribute: kAXRoleAttribute as CFString) ?? "nil"
        let subrole = geometryProbeAttributeString(axElement, attribute: kAXSubroleAttribute as CFString) ?? "nil"
        return (role, subrole)
    }

    private func editableElementFrame(_ axElement: AXUIElement) -> CGRect? {
        var positionValue: CFTypeRef?
        let positionErr = AXUIElementCopyAttributeValue(axElement, kAXPositionAttribute as CFString, &positionValue)
        var sizeValue: CFTypeRef?
        let sizeErr = AXUIElementCopyAttributeValue(axElement, kAXSizeAttribute as CFString, &sizeValue)
        guard positionErr == .success,
              sizeErr == .success,
              let position = geometryProbeAXPoint(positionValue),
              let size = geometryProbeAXSize(sizeValue) else {
            return nil
        }
        return CGRect(origin: position, size: size)
    }

    private func editableElementHasTextSupport(_ axElement: AXUIElement) -> Bool {
        var valueRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(axElement, kAXValueAttribute as CFString, &valueRef) == .success, valueRef != nil {
            return true
        }

        var rangeRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(axElement, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success, rangeRef != nil {
            return true
        }

        var markerRangeRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(axElement, "AXSelectedTextMarkerRange" as CFString, &markerRangeRef) == .success, markerRangeRef != nil {
            return true
        }

        return false
    }

    private func rememberEditableElement(_ axElement: AXUIElement, source: String) {
        let pid = editableElementPID(axElement)
        guard pid != 0, pid != NSRunningApplication.current.processIdentifier else { return }

        let roleInfo = editableElementRoleInfo(axElement)
        guard isEditableAXRole(role: roleInfo.role, subrole: roleInfo.subrole) else { return }
        guard editableElementFrame(axElement).map({ !$0.isEmpty }) == true else { return }
        guard editableElementHasTextSupport(axElement) else { return }

        editableElementLock.lock()
        lastEditableElement = axElement
        lastEditableElementPID = pid
        lastEditableElementRole = roleInfo.role
        lastEditableElementTimestamp = CFAbsoluteTimeGetCurrent()
        editableElementLock.unlock()

        print("[EditableResolver] remembered source=\(source) role=\(roleInfo.role) pid=\(pid)")
    }

    private func invalidateRememberedEditableElement(reason: String) {
        editableElementLock.lock()
        lastEditableElement = nil
        lastEditableElementPID = 0
        lastEditableElementRole = ""
        lastEditableElementTimestamp = 0
        editableElementLock.unlock()

        print("[EditableResolver] invalidated reason=\(reason)")
    }

    private func validateEditableElement(
        _ axElement: AXUIElement,
        expectedPID: pid_t,
        source: String,
        isRecovered: Bool
    ) -> EditableElementResolution? {
        let pid = editableElementPID(axElement)
        guard pid == expectedPID else {
            print("[EditableResolver] rejected reason=pidMismatch source=\(source) expectedPID=\(expectedPID) actualPID=\(pid)")
            return nil
        }
        guard pid != NSRunningApplication.current.processIdentifier else {
            print("[EditableResolver] rejected reason=overlayElement source=\(source) pid=\(pid)")
            return nil
        }

        let roleInfo = editableElementRoleInfo(axElement)
        guard isEditableAXRole(role: roleInfo.role, subrole: roleInfo.subrole) else {
            print("[EditableResolver] rejected reason=roleNotEditable source=\(source) role=\(roleInfo.role) subrole=\(roleInfo.subrole)")
            return nil
        }

        guard let frame = editableElementFrame(axElement), !frame.isEmpty else {
            print("[EditableResolver] rejected reason=emptyFrame source=\(source) role=\(roleInfo.role) pid=\(pid)")
            return nil
        }

        guard editableElementHasTextSupport(axElement) else {
            print("[EditableResolver] rejected reason=noAXValue source=\(source) role=\(roleInfo.role) pid=\(pid)")
            return nil
        }

        print("[EditableResolver] resolved source=\(source) role=\(roleInfo.role) pid=\(pid)")
        rememberEditableElement(axElement, source: source)
        return EditableElementResolution(
            element: axElement,
            source: source,
            role: roleInfo.role,
            subrole: roleInfo.subrole,
            pid: pid,
            isRecovered: isRecovered
        )
    }

    private func appScopedFocusedElement(pid: pid_t) -> AXUIElement? {
        let appElement = AXUIElementCreateApplication(pid)
        var focusedElement: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedElement)
        guard err == .success, let element = focusedElement else {
            print("[EditableResolver] appScopedFocusedElement available=false role=nil error=\(geometryProbeError(err))")
            return nil
        }
        let axElement = element as! AXUIElement
        let roleInfo = editableElementRoleInfo(axElement)
        print("[EditableResolver] appScopedFocusedElement available=true role=\(roleInfo.role)")
        return axElement
    }

    private func cachedTextExtractionElement() -> (element: AXUIElement, ageMs: Double, samePID: Bool)? {
        let focusedPID = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0
        editableElementLock.lock()
        let element = lastEditableElement
        let pid = lastEditableElementPID
        let timestamp = lastEditableElementTimestamp
        editableElementLock.unlock()

        guard let element else { return nil }
        let ageMs = (CFAbsoluteTimeGetCurrent() - timestamp) * 1000
        return (element, ageMs, pid == focusedPID)
    }

    private func firstObservedEditableElement(in root: AXUIElement, expectedPID: pid_t) -> AXUIElement? {
        var queue: [AXUIElement] = [root]
        var visited = 0
        let maxVisited = 160

        while !queue.isEmpty && visited < maxVisited {
            let element = queue.removeFirst()
            visited += 1

            if editableElementPID(element) == expectedPID {
                let roleInfo = editableElementRoleInfo(element)
                if isEditableAXRole(role: roleInfo.role, subrole: roleInfo.subrole),
                   editableElementFrame(element).map({ !$0.isEmpty }) == true,
                   editableElementHasTextSupport(element) {
                    return element
                }
            }

            var childrenRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
                  let children = childrenRef as? [AXUIElement] else {
                continue
            }
            queue.append(contentsOf: children.prefix(max(0, maxVisited - visited)))
        }

        return nil
    }

    private func resolveEditableElementForGeometry(
        systemFocusedElement: AXUIElement?,
        systemFocusedError: AXError,
        focusedPID: pid_t
    ) -> EditableElementResolution? {
        print("[EditableResolver] systemFocusedElement available=\(systemFocusedElement != nil)")

        if let systemFocusedElement,
           let resolution = validateEditableElement(
                systemFocusedElement,
                expectedPID: focusedPID,
                source: "systemFocused",
                isRecovered: false
           ) {
            return resolution
        }

        if systemFocusedElement == nil {
            print("[EditableResolver] systemFocusedElement unavailable error=\(geometryProbeError(systemFocusedError))")
        }

        if let appFocused = appScopedFocusedElement(pid: focusedPID),
           let resolution = validateEditableElement(
                appFocused,
                expectedPID: focusedPID,
                source: "appScopedFocused",
                isRecovered: true
           ) {
            return resolution
        }

        if let cached = cachedTextExtractionElement() {
            let roleInfo = editableElementRoleInfo(cached.element)
            print("[EditableResolver] reusedTextExtractionElement available=true role=\(roleInfo.role)")
            print("[EditableResolver] reusedLastEditableElement available=true ageMs=\(String(format: "%.1f", cached.ageMs)) samePID=\(cached.samePID)")
            if cached.samePID,
               cached.ageMs < 10_000,
               let resolution = validateEditableElement(
                    cached.element,
                    expectedPID: focusedPID,
                    source: "textExtractionElement",
                    isRecovered: true
               ) {
                return resolution
            } else if !cached.samePID {
                print("[EditableResolver] rejected reason=pidMismatch source=lastEditable expectedPID=\(focusedPID)")
            } else {
                print("[EditableResolver] rejected reason=staleSession source=lastEditable ageMs=\(String(format: "%.1f", cached.ageMs))")
            }
        } else {
            print("[EditableResolver] reusedTextExtractionElement available=false role=nil")
            print("[EditableResolver] reusedLastEditableElement available=false ageMs=nil samePID=false")
        }

        let appElement = AXUIElementCreateApplication(focusedPID)
        if let observed = firstObservedEditableElement(in: appElement, expectedPID: focusedPID),
           let resolution = validateEditableElement(
                observed,
                expectedPID: focusedPID,
                source: "observedEditable",
                isRecovered: true
           ) {
            return resolution
        }

        return nil
    }

    func getCurrentCaretRect(requestID: UInt64? = nil) -> CGRect? {
        let startedAt = CFAbsoluteTimeGetCurrent()
        let focusedPID = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0
        let appName = NSWorkspace.shared.frontmostApplication?.localizedName ?? "unknown"
        let systemWideElement = AXUIElementCreateSystemWide()
        var focusedElement: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(systemWideElement, kAXFocusedUIElementAttribute as CFString, &focusedElement)
        let systemFocusedElement = (err == .success ? focusedElement : nil).map { $0 as! AXUIElement }

        guard let resolution = resolveEditableElementForGeometry(
            systemFocusedElement: systemFocusedElement,
            systemFocusedError: err,
            focusedPID: focusedPID
        ) else {
            let elapsedMs = (CFAbsoluteTimeGetCurrent() - startedAt) * 1000
            print("[GeometryProbe] start requestID=\(geometryProbeID(requestID)) focusedPID=\(focusedPID) app=\(appName) role=nil subrole=nil")
            print("[GeometryProbe] finalGeometry unavailable reason=focusedElementUnavailable error=\(geometryProbeError(err))")
            print("[GeometryProbe] timingMs=\(String(format: "%.1f", elapsedMs))")
            return nil
        }
        let axElement = resolution.element
        let role = resolution.role
        let subrole = resolution.subrole
        print("[GeometryProbe] start requestID=\(geometryProbeID(requestID)) focusedPID=\(focusedPID) app=\(appName) role=\(role) subrole=\(subrole)")

        var positionValue: CFTypeRef?
        let positionErr = AXUIElementCopyAttributeValue(axElement, kAXPositionAttribute as CFString, &positionValue)
        var sizeValue: CFTypeRef?
        let sizeErr = AXUIElementCopyAttributeValue(axElement, kAXSizeAttribute as CFString, &sizeValue)
        let focusedPosition = geometryProbeAXPoint(positionValue)
        let focusedSize = geometryProbeAXSize(sizeValue)
        let focusedFrame: CGRect?
        if let focusedPosition, let focusedSize {
            focusedFrame = CGRect(origin: focusedPosition, size: focusedSize)
        } else {
            focusedFrame = nil
        }
        print("[GeometryProbe] focusedElementFrame available=\(focusedFrame != nil) rect=\(geometryProbeRect(focusedFrame)) positionError=\(geometryProbeError(positionErr)) sizeError=\(geometryProbeError(sizeErr))")

        // --- Priority: WebKit/Chromium AXTextMarker ---
        let markerRangeAttr = "AXSelectedTextMarkerRange" as CFString
        let boundsForRangeAttr = "AXBoundsForTextMarkerRange" as CFString

        var rangeValue: CFTypeRef?
        let rangeErr = AXUIElementCopyAttributeValue(axElement, markerRangeAttr, &rangeValue)

        if rangeErr == .success, let range = rangeValue {
            var boundsValue: CFTypeRef?
            let boundsErr = AXUIElementCopyParameterizedAttributeValue(axElement, boundsForRangeAttr, range, &boundsValue)
            let rect = geometryProbeAXRect(boundsValue)
            print("[GeometryProbe] browserTextMarkerRange available=true boundsAvailable=\(rect != nil) rect=\(geometryProbeRect(rect)) error=\(geometryProbeError(boundsErr))")
            if boundsErr == .success {
                if let rect, rect != .zero {
                    // Suppressed: print("[TypeFlow-Debug] Browser Caret found via AXTextMarker: \(rect)")
                    let elapsedMs = (CFAbsoluteTimeGetCurrent() - startedAt) * 1000
                    print("[GeometryProbe] coordinateConversion available=true rect=\(geometryProbeRect(rect))")
                    print("[GeometryProbe] finalGeometry available=true source=browserTextMarker rect=\(geometryProbeRect(rect))")
                    print("[GeometryProbe] timingMs=\(String(format: "%.1f", elapsedMs))")
                    return rect
                }
            }
        } else {
            print("[GeometryProbe] browserTextMarkerRange available=false boundsAvailable=false rect=nil error=\(geometryProbeError(rangeErr))")
        }
        print("[TypeFlow-Debug] Browser AXTextMarker extraction failed.")

        // --- Standard fallback for native macOS apps ---
        var selectedRangeRef: CFTypeRef?
        let selectedRangeErr = AXUIElementCopyAttributeValue(axElement, kAXSelectedTextRangeAttribute as CFString, &selectedRangeRef)
        if selectedRangeErr == .success,
           let selectedRangeRef,
           CFGetTypeID(selectedRangeRef) == AXValueGetTypeID() {
            let rangeValue = selectedRangeRef as! AXValue
            var range = CFRange(location: 0, length: 0)
            AXValueGetValue(rangeValue, .cfRange, &range)

            print("[GeometryProbe] selectedRange available=true location=\(range.location) length=\(range.length)")

            // Try getting the bounds of the range directly
            var bounds: CFTypeRef?
            let selectedBoundsErr = AXUIElementCopyParameterizedAttributeValue(axElement, kAXBoundsForRangeParameterizedAttribute as CFString, rangeValue, &bounds)
            let selectedBoundsRect = geometryProbeAXRect(bounds)
            print("[GeometryProbe] boundsForSelectedRange available=\(selectedBoundsRect != nil) rect=\(geometryProbeRect(selectedBoundsRect)) error=\(geometryProbeError(selectedBoundsErr))")
            var selectedBoundsReturnRect: CGRect?
            if selectedBoundsErr == .success, let rect = selectedBoundsRect, rect.width > 0 || rect.height > 0 {
                selectedBoundsReturnRect = rect
            } else {
                selectedBoundsReturnRect = nil
            }

            var zeroLengthReturnRect: CGRect?
            var zeroLengthRange = CFRange(location: range.location, length: 0)
            if let zeroLengthValue = AXValueCreate(.cfRange, &zeroLengthRange) {
                var zeroBounds: CFTypeRef?
                let zeroBoundsErr = AXUIElementCopyParameterizedAttributeValue(axElement, kAXBoundsForRangeParameterizedAttribute as CFString, zeroLengthValue, &zeroBounds)
                let zeroBoundsRect = geometryProbeAXRect(zeroBounds)
                print("[GeometryProbe] boundsForZeroLengthCaretRange available=\(zeroBoundsRect != nil) rect=\(geometryProbeRect(zeroBoundsRect)) error=\(geometryProbeError(zeroBoundsErr))")
                if zeroBoundsErr == .success, let rect = zeroBoundsRect, rect.width > 0 || rect.height > 0 {
                    zeroLengthReturnRect = rect
                }
            } else {
                print("[GeometryProbe] boundsForZeroLengthCaretRange available=false rect=nil error=createRangeFailed")
            }

            // If the range length is 0 (caret only), try to query range of length 1 around it
            var previousCharReturnRect: CGRect?
            var nextCharReturnRect: CGRect?
            if range.length == 0 {
                // Try char before caret
                if range.location > 0 {
                    var fallbackRange = CFRange(location: range.location - 1, length: 1)
                    if let fallbackValue = AXValueCreate(.cfRange, &fallbackRange) {
                        var charBounds: CFTypeRef?
                        let previousCharErr = AXUIElementCopyParameterizedAttributeValue(axElement, kAXBoundsForRangeParameterizedAttribute as CFString, fallbackValue, &charBounds)
                        let previousCharRect = geometryProbeAXRect(charBounds)
                        print("[GeometryProbe] boundsForPreviousCharRange available=\(previousCharRect != nil) rect=\(geometryProbeRect(previousCharRect)) error=\(geometryProbeError(previousCharErr))")
                        if previousCharErr == .success, let rect = previousCharRect {
                            if rect.width > 0 || rect.height > 0 {
                                previousCharReturnRect = CGRect(x: rect.origin.x + rect.width, y: rect.origin.y, width: 0, height: rect.height)
                            }
                        }
                    } else {
                        print("[GeometryProbe] boundsForPreviousCharRange available=false rect=nil error=createRangeFailed")
                    }
                } else {
                    print("[GeometryProbe] boundsForPreviousCharRange available=false rect=nil error=caretAtStart")
                }
                
                // Try char at caret
                var fallbackRange = CFRange(location: range.location, length: 1)
                if let fallbackValue = AXValueCreate(.cfRange, &fallbackRange) {
                    var charBounds: CFTypeRef?
                    let nextCharErr = AXUIElementCopyParameterizedAttributeValue(axElement, kAXBoundsForRangeParameterizedAttribute as CFString, fallbackValue, &charBounds)
                    let nextCharRect = geometryProbeAXRect(charBounds)
                    print("[GeometryProbe] boundsForNextCharRange available=\(nextCharRect != nil) rect=\(geometryProbeRect(nextCharRect)) error=\(geometryProbeError(nextCharErr))")
                    if nextCharErr == .success, let rect = nextCharRect {
                        if rect.width > 0 || rect.height > 0 {
                            nextCharReturnRect = CGRect(x: rect.origin.x, y: rect.origin.y, width: 0, height: rect.height)
                        }
                    }
                } else {
                    print("[GeometryProbe] boundsForNextCharRange available=false rect=nil error=createRangeFailed")
                }
            }

            if resolution.isRecovered, let zeroLengthReturnRect {
                let elapsedMs = (CFAbsoluteTimeGetCurrent() - startedAt) * 1000
                print("[GeometryProbe] coordinateConversion available=true rect=\(geometryProbeRect(zeroLengthReturnRect))")
                print("[GeometryProbe] finalGeometry available=true source=zeroLengthCaretBounds rect=\(geometryProbeRect(zeroLengthReturnRect))")
                print("[GeometryProbe] timingMs=\(String(format: "%.1f", elapsedMs))")
                return zeroLengthReturnRect
            }
            if let selectedBoundsReturnRect {
                let elapsedMs = (CFAbsoluteTimeGetCurrent() - startedAt) * 1000
                print("[GeometryProbe] coordinateConversion available=true rect=\(geometryProbeRect(selectedBoundsReturnRect))")
                print("[GeometryProbe] finalGeometry available=true source=selectedRangeBounds rect=\(geometryProbeRect(selectedBoundsReturnRect))")
                print("[GeometryProbe] timingMs=\(String(format: "%.1f", elapsedMs))")
                return selectedBoundsReturnRect
            }
            if let zeroLengthReturnRect {
                let elapsedMs = (CFAbsoluteTimeGetCurrent() - startedAt) * 1000
                print("[GeometryProbe] coordinateConversion available=true rect=\(geometryProbeRect(zeroLengthReturnRect))")
                print("[GeometryProbe] finalGeometry available=true source=zeroLengthCaretBounds rect=\(geometryProbeRect(zeroLengthReturnRect))")
                print("[GeometryProbe] timingMs=\(String(format: "%.1f", elapsedMs))")
                return zeroLengthReturnRect
            }
            if let previousCharReturnRect {
                let elapsedMs = (CFAbsoluteTimeGetCurrent() - startedAt) * 1000
                print("[GeometryProbe] coordinateConversion available=true rect=\(geometryProbeRect(previousCharReturnRect))")
                print("[GeometryProbe] finalGeometry available=true source=previousCharBounds rect=\(geometryProbeRect(previousCharReturnRect))")
                print("[GeometryProbe] timingMs=\(String(format: "%.1f", elapsedMs))")
                return previousCharReturnRect
            }
            if let nextCharReturnRect {
                let elapsedMs = (CFAbsoluteTimeGetCurrent() - startedAt) * 1000
                print("[GeometryProbe] coordinateConversion available=true rect=\(geometryProbeRect(nextCharReturnRect))")
                print("[GeometryProbe] finalGeometry available=true source=nextCharRange rect=\(geometryProbeRect(nextCharReturnRect))")
                print("[GeometryProbe] timingMs=\(String(format: "%.1f", elapsedMs))")
                return nextCharReturnRect
            }
        } else {
            print("[GeometryProbe] selectedRange available=false location=nil length=nil error=\(geometryProbeError(selectedRangeErr))")
            print("[GeometryProbe] boundsForSelectedRange available=false rect=nil error=noSelectedRange")
            print("[GeometryProbe] boundsForZeroLengthCaretRange available=false rect=nil error=noSelectedRange")
            print("[GeometryProbe] boundsForPreviousCharRange available=false rect=nil error=noSelectedRange")
        }
        
        
        // Fallback: use focused element's bottom-left corner with offset
        if let pos = focusedPosition, let size = focusedSize {
            let textLength = self.keystrokeBuffer.count
            
            let estimatedTextWidth = CGFloat(textLength) * 8.0
            
            let fallbackX = pos.x + 5 + estimatedTextWidth
            let fallbackY = pos.y + max(0, size.height - 18)
            print("[TypeFlow] Caret bounds failed, falling back to element bottom-left (offset): x=\(fallbackX), y=\(fallbackY), size=\(size), textLength=\(textLength)")
            let finalRect = CGRect(x: fallbackX, y: fallbackY, width: 0, height: 15)
            let elapsedMs = (CFAbsoluteTimeGetCurrent() - startedAt) * 1000
            print("[GeometryProbe] coordinateConversion available=true rect=\(geometryProbeRect(finalRect))")
            print("[GeometryProbe] finalGeometry available=true source=elementFrameEstimated rect=\(geometryProbeRect(finalRect))")
            print("[GeometryProbe] timingMs=\(String(format: "%.1f", elapsedMs))")
            return finalRect
        }

        let elapsedMs = (CFAbsoluteTimeGetCurrent() - startedAt) * 1000
        print("[GeometryProbe] coordinateConversion available=false rect=nil")
        print("[GeometryProbe] finalGeometry unavailable reason=noTextMarkerNoRangeNoElementFrame")
        print("[GeometryProbe] timingMs=\(String(format: "%.1f", elapsedMs))")
        return nil
    }

    private func getFocusedElement() -> AXUIElement? {
        let systemWideElement = AXUIElementCreateSystemWide()
        var focusedElement: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(systemWideElement, kAXFocusedUIElementAttribute as CFString, &focusedElement)
        guard err == .success, let element = focusedElement else { return nil }
        let axElement = element as! AXUIElement
        rememberEditableElement(axElement, source: "textExtraction")
        return axElement
    }

    func clearKeystrokeBuffer() {
        if !keystrokeBuffer.isEmpty {
            logContextAudit("clearKeystrokeBuffer oldLen=\(keystrokeBuffer.count) oldBuffer='\(contextAuditPreview(keystrokeBuffer))'")
        }
        keystrokeBuffer = ""
        invalidateRememberedEditableElement(reason: "bufferCleared")
        // Suppressed: print("[TypeFlow-Debug] Keystroke buffer cleared")
    }

    func synchronizeKeystrokeBuffer(withCanonicalText text: String, source: TextBeforeCaretSource) {
        guard source != .keystrokeBufferFallback && source != .none else { return }

        guard !hasPendingPrintableKeys() else {
            logContextAudit("syncKeystrokeBuffer deferred source=\(source.rawValue) pendingPrintableKeys=true proposedLen=\(text.count) proposedBuffer='\(contextAuditPreview(text))' liveBufferLen=\(keystrokeBuffer.count) liveBuffer='\(contextAuditPreview(keystrokeBuffer))'")
            return
        }

        let canonicalSuffix = text.count > 150 ? String(text.suffix(150)) : text
        guard keystrokeBuffer != canonicalSuffix else { return }

        logContextAudit("syncKeystrokeBuffer source=\(source.rawValue) oldLen=\(keystrokeBuffer.count) oldBuffer='\(contextAuditPreview(keystrokeBuffer))' newLen=\(canonicalSuffix.count) newBuffer='\(contextAuditPreview(canonicalSuffix))'")
        keystrokeBuffer = canonicalSuffix
    }
    
    private func capKeystrokeBuffer() {
        if keystrokeBuffer.count > 150 {
            keystrokeBuffer = String(keystrokeBuffer.suffix(150))
        }
    }
    
    func handleKeystroke(keyCode: Int64, event: CGEvent, skipPrintableAppend: Bool = false) {
        // Navigation / Action keys that reset the buffer
        // 36: Return, 76: Enter (numpad), 53: Escape, 48: Tab
        // 123: Left, 124: Right, 125: Down, 126: Up
        // 115: Home, 119: End, 116: PageUp, 121: PageDown
        if [36, 76, 53, 48, 123, 124, 125, 126, 115, 119, 116, 121].contains(keyCode) {
            if keyCode == 36 || keyCode == 76 {
                let trimmed = keystrokeBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.count >= 5 {
                    DispatchQueue.global(qos: .userInitiated).async {
                        print("[TypeFlow-Debug] Return pressed. Logging keystroke buffer to history: '\(trimmed)'")
                        TypingHistoryManager.shared.logSentence(trimmed)
                    }
                }
                CompletionManager.shared.handleReturnPressed()
            }
            clearKeystrokeBuffer()
            lastDeletedWord = nil
            return
        }
        
        // Space (49), Tab (48), or Punctuation (comma 43, period 47) finishes a word
        if keyCode == 49 || keyCode == 48 || keyCode == 43 || keyCode == 47 {

            if let deleted = lastDeletedWord, !deleted.isEmpty {
                let newWord = keystrokeBuffer.components(separatedBy: .whitespacesAndNewlines).last?.trimmingCharacters(in: .punctuationCharacters) ?? ""
                let deletedClean = deleted.trimmingCharacters(in: .punctuationCharacters)
                
                if !newWord.isEmpty && newWord != deletedClean && newWord.count > 1 {
                    DispatchQueue.global(qos: .userInitiated).async {
                        var lexicon = UserDefaults.standard.stringArray(forKey: "UserCustomLexicon") ?? []
                        if !lexicon.contains(newWord) {
                            lexicon.append(newWord)
                            UserDefaults.standard.set(lexicon, forKey: "UserCustomLexicon")
                            print("[TypeFlow-Debug] Dynamic Lexicon: Added '\(newWord)' to UserCustomLexicon (replaced '\(deletedClean)')")
                            DispatchQueue.main.async {
                                NSSpellChecker.shared.learnWord(newWord)
                            }
                        }
                    }
                }
                lastDeletedWord = nil
            }
        }
        
        // Delete / Backspace (51)
        if keyCode == 51 {
            if !isBackspacing {
                // ── Non-Blocking Backspace: do NOT call getTextBeforeCaret() here. ──
                // getTextBeforeCaret() is a synchronous AX IPC call. Calling it from
                // inside the tapQueue (event processing path) blocks the event tap
                // thread, causing macOS to drop subsequent key events (the 'R' key
                // hijack bug). Instead, capture the last word directly from the
                // keystroke buffer, which is always available with zero latency.
                let bufferWords = keystrokeBuffer.components(separatedBy: .whitespacesAndNewlines)
                lastDeletedWord = bufferWords.last
                isBackspacing = true
            }
            if !keystrokeBuffer.isEmpty {
                keystrokeBuffer.removeLast()
                // Suppressed: print("[TypeFlow-Debug] Backspace: buffer is now '\(keystrokeBuffer)'")
            }
            return
        } else {
            isBackspacing = false
        }
        
        // Check for modifier keys (Command/Control) that represent shortcuts
        let flags = event.flags
        if flags.contains(.maskCommand) || flags.contains(.maskControl) {
            clearKeystrokeBuffer()
            return
        }

        if skipPrintableAppend {
            logContextAudit("handleKeystroke appendSkipped keyCode=\(keyCode) keystrokeBufferLen=\(keystrokeBuffer.count) keystrokeBuffer='\(contextAuditPreview(keystrokeBuffer))'")
            return
        }
        
        // Extract Unicode characters from the event
        var characters: String = ""
        var actualLength = 0
        var unicodeChars = [UniChar](repeating: 0, count: 16)
        event.keyboardGetUnicodeString(maxStringLength: 16, actualStringLength: &actualLength, unicodeString: &unicodeChars)
        if actualLength > 0 {
            characters = String(utf16CodeUnits: unicodeChars, count: actualLength)
        }
        
        if !characters.isEmpty {
            let filtered = characters.filter { !$0.isASCII || ($0.asciiValue ?? 0) >= 32 }
            if !filtered.isEmpty {
                keystrokeBuffer += filtered
                capKeystrokeBuffer()
                logContextAudit("handleKeystroke appended='\(contextAuditPreview(String(filtered)))' keyCode=\(keyCode) keystrokeBufferLen=\(keystrokeBuffer.count) keystrokeBuffer='\(contextAuditPreview(keystrokeBuffer))'")
                // Suppressed: print("[TypeFlow-Debug] Typed: '\(filtered)', buffer is now '\(keystrokeBuffer)'")
            }
        }
    }

    func getTextBeforeCaret() -> String? {
        return getTextBeforeCaretSnapshot()?.text
    }

    func getTextBeforeCaretSnapshot() -> TextBeforeCaretSnapshot? {
        logContextAudit("getTextBeforeCaret start keystrokeBufferLen=\(keystrokeBuffer.count) liveBuffer='\(contextAuditPreview(keystrokeBuffer))'")
        guard let axElement = getFocusedElement() else {
            print("[TypeFlow-Debug] AX: No focused element found")
            if !keystrokeBuffer.isEmpty {
                print("[TypeFlow-Debug] AX: Using buffer: '\(keystrokeBuffer.suffix(40))' (Len: \(keystrokeBuffer.count))")
                logContextAudit("getTextBeforeCaret method=keystrokeBuffer-noFocusedElement focusedTextLen=0 selectedTextLen=0 textBeforeCaretLen=\(keystrokeBuffer.count) textBeforeCaret='\(contextAuditPreview(keystrokeBuffer))'")
                return TextBeforeCaretSnapshot(text: keystrokeBuffer, source: .keystrokeBufferFallback)
            }
            logContextAudit("getTextBeforeCaret method=none-noFocusedElement focusedTextLen=0 selectedTextLen=0 textBeforeCaretLen=0")
            return nil
        }
        
        // --- Fallback 1: kAXValueAttribute + kAXSelectedTextRangeAttribute ---
        var valueRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(axElement, kAXValueAttribute as CFString, &valueRef) == .success,
           let val = valueRef {
            var fullText: String?
            if let stringValue = val as? String {
                fullText = stringValue
            } else if CFGetTypeID(val) == CFAttributedStringGetTypeID() {
                let attrStr = val as! CFAttributedString
                fullText = CFAttributedStringGetString(attrStr) as String
            }
            
            if let fullText = fullText {
                var rangeRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(axElement, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success,
                   let rangeVal = rangeRef {
                    var range = CFRange(location: 0, length: 0)
                    AXValueGetValue(rangeVal as! AXValue, .cfRange, &range)
                    let cursorIndex = range.location
                    
                    let utf16 = fullText.utf16
                    let safeCursorIndex = max(0, min(cursorIndex, utf16.count))
                    if let sliceEnd = utf16.index(utf16.startIndex, offsetBy: safeCursorIndex, limitedBy: utf16.endIndex) {
                        let textBeforeCursor = String(fullText[..<sliceEnd])
                        let result = String(textBeforeCursor.suffix(1000))
                        if !result.isEmpty {
                            print("[TypeFlow-Debug] AX kAXValue: '\(result.suffix(40))' (Len: \(result.count))")
                            logContextAudit("getTextBeforeCaret method=kAXValue focusedTextLen=\(fullText.count) selectedRangeLocation=\(range.location) selectedRangeLength=\(range.length) selectedTextLen=\(range.length) textBeforeCaretLen=\(result.count) focusedText='\(contextAuditPreview(fullText))' textBeforeCaret='\(contextAuditPreview(result))' liveBufferLen=\(keystrokeBuffer.count) liveBuffer='\(contextAuditPreview(keystrokeBuffer))'")
                            return TextBeforeCaretSnapshot(text: result, source: .axValue)
                        }
                    }
                }
            }
        }
        
        // --- Fallback 2: kAXSelectedTextAttribute ---
        var selectedTextRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(axElement, kAXSelectedTextAttribute as CFString, &selectedTextRef) == .success,
           let selectedText = selectedTextRef as? String,
           !selectedText.isEmpty {
            let result = String(selectedText.suffix(1000))
            print("[TypeFlow-Debug] AX kAXSelectedText: '\(result.suffix(40))' (Len: \(result.count))")
            logContextAudit("getTextBeforeCaret method=kAXSelectedText focusedTextLen=unknown selectedTextLen=\(selectedText.count) textBeforeCaretLen=\(result.count) textBeforeCaret='\(contextAuditPreview(result))' liveBufferLen=\(keystrokeBuffer.count) liveBuffer='\(contextAuditPreview(keystrokeBuffer))'")
            return TextBeforeCaretSnapshot(text: result, source: .axSelectedText)
        }
        
        // --- Fallback 3: kAXStringForRangeParameterizedAttribute ---
        var selectedRangeRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(axElement, kAXSelectedTextRangeAttribute as CFString, &selectedRangeRef) == .success,
           let rangeValue = selectedRangeRef {
            var range = CFRange(location: 0, length: 0)
            AXValueGetValue(rangeValue as! AXValue, .cfRange, &range)
            
            let length = min(1000, range.location)
            let startLocation = range.location - length
            let fetchRange = CFRange(location: startLocation, length: length)
            var fetchRangeValue = fetchRange
            
            if let axFetchRange = AXValueCreate(.cfRange, &fetchRangeValue) {
                var stringRef: CFTypeRef?
                if AXUIElementCopyParameterizedAttributeValue(axElement, kAXStringForRangeParameterizedAttribute as CFString, axFetchRange, &stringRef) == .success,
                   let string = stringRef as? String,
                   !string.isEmpty {
                    print("[TypeFlow-Debug] AX kAXStringForRange: '\(string.suffix(40))' (Len: \(string.count))")
                    logContextAudit("getTextBeforeCaret method=kAXStringForRange focusedTextLen=unknown selectedRangeLocation=\(range.location) selectedRangeLength=\(range.length) selectedTextLen=\(range.length) textBeforeCaretLen=\(string.count) textBeforeCaret='\(contextAuditPreview(string))' liveBufferLen=\(keystrokeBuffer.count) liveBuffer='\(contextAuditPreview(keystrokeBuffer))'")
                    return TextBeforeCaretSnapshot(text: string, source: .axStringForRange)
                }
            }
        }
        
        // --- Fallback 4: CGEvent keystroke buffer ---
        if !keystrokeBuffer.isEmpty {
            print("[TypeFlow-Debug] AX Fallback Buffer: '\(keystrokeBuffer.suffix(40))' (Len: \(keystrokeBuffer.count))")
            logContextAudit("getTextBeforeCaret method=keystrokeBuffer-axFallback focusedTextLen=unknown selectedTextLen=unknown textBeforeCaretLen=\(keystrokeBuffer.count) textBeforeCaret='\(contextAuditPreview(keystrokeBuffer))'")
            return TextBeforeCaretSnapshot(text: keystrokeBuffer, source: .keystrokeBufferFallback)
        }
        
        print("[TypeFlow-Debug] AX: all extraction methods failed, active line is empty")
        logContextAudit("getTextBeforeCaret method=none focusedTextLen=unknown selectedTextLen=unknown textBeforeCaretLen=0 liveBufferLen=0")
        return nil
    }
    
    func getFullFieldText() -> String? {
        let systemWideElement = AXUIElementCreateSystemWide()
        var focusedElement: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(systemWideElement, kAXFocusedUIElementAttribute as CFString, &focusedElement)
        
        if err == .success, let element = focusedElement {
            let axElement = element as! AXUIElement
            
            // Try to get the entire value first
            var valueRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(axElement, kAXValueAttribute as CFString, &valueRef) == .success,
               let val = valueRef {
                var stringValue: String?
                if let str = val as? String {
                    stringValue = str
                } else if CFGetTypeID(val) == CFAttributedStringGetTypeID() {
                    let attrStr = val as! CFAttributedString
                    stringValue = CFAttributedStringGetString(attrStr) as String
                }
                
                if let stringVal = stringValue {
                    // Truncate if too long (e.g. 4000 chars)
                    if stringVal.count > 4000 {
                        return "..." + String(stringVal.suffix(4000))
                    }
                    return stringVal
                }
            }
            
            // If that fails, try to fetch a large range around the caret
            var selectedRangeRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(axElement, kAXSelectedTextRangeAttribute as CFString, &selectedRangeRef) == .success {
                let rangeValue = selectedRangeRef as! AXValue
                var range = CFRange(location: 0, length: 0)
                AXValueGetValue(rangeValue, .cfRange, &range)
                
                let length = min(2000, range.location)
                let startLocation = range.location - length
                // Fetch 2000 before and 2000 after
                let fetchRange = CFRange(location: startLocation, length: length + 2000)
                
                var fetchRangeValue = fetchRange
                guard let axFetchRange = AXValueCreate(.cfRange, &fetchRangeValue) else { return nil }
                
                var stringRef: CFTypeRef?
                if AXUIElementCopyParameterizedAttributeValue(axElement, kAXStringForRangeParameterizedAttribute as CFString, axFetchRange, &stringRef) == .success {
                    if let string = stringRef as? String {
                        return string
                    }
                }
            }
        }
        return nil
    }
    
    func getAXVisibleScreenText() -> String? {
        guard let focused = getFocusedElement() else { return nil }
        var current: AXUIElement = focused
        var rootElement: AXUIElement = focused
        
        for _ in 0..<15 {
            var roleRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(current, kAXRoleAttribute as CFString, &roleRef) == .success,
               let role = roleRef as? String {
                if role == "AXWebArea" || role == "AXWindow" {
                    rootElement = current
                    if role == "AXWebArea" {
                        break
                    }
                }
            }
            var parentRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(current, kAXParentAttribute as CFString, &parentRef) == .success {
                current = parentRef as! AXUIElement
            } else {
                break
            }
        }
        
        var textPieces: [String] = []
        var queue: [AXUIElement] = [rootElement]
        var visited = 0
        
        // Helper to check if two AXUIElements are the same
        func isSameElement(_ el1: AXUIElement, _ el2: AXUIElement) -> Bool {
            return CFEqual(el1, el2)
        }
        
        while !queue.isEmpty && visited < 150 {
            let el = queue.removeFirst()
            visited += 1
            
            // Skip the focused editor element entirely to avoid self-matching
            if isSameElement(el, focused) {
                continue
            }
            
            var roleRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(el, kAXRoleAttribute as CFString, &roleRef) == .success,
               let role = roleRef as? String {
                if role == "AXStaticText" || role == "AXTextArea" || role == "AXTextField" {
                    var valueRef: CFTypeRef?
                    if AXUIElementCopyAttributeValue(el, kAXValueAttribute as CFString, &valueRef) == .success,
                       let val = valueRef as? String, !val.isEmpty {
                        textPieces.append(val)
                    }
                } else {
                    if role == "AXHeading" || role == "AXLink" {
                        var titleRef: CFTypeRef?
                        if AXUIElementCopyAttributeValue(el, kAXTitleAttribute as CFString, &titleRef) == .success,
                           let title = titleRef as? String, !title.isEmpty {
                            textPieces.append(title)
                        }
                    }
                    var childrenRef: CFTypeRef?
                    if AXUIElementCopyAttributeValue(el, kAXChildrenAttribute as CFString, &childrenRef) == .success,
                       let children = childrenRef as? [AXUIElement] {
                        queue.append(contentsOf: children)
                    }
                }
            }
        }
        return textPieces.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Browser/page context extraction (full AXWebArea BFS)
    //
    // Must be called OFF the keystroke hot path (on focus/idle/page-change only).
    // Returns up to 3000 chars of page text, excluding the active input field.

    struct PageContextResult {
        let text: String
        let source: String      // "AXWebArea" | "AXWindow" | "traversal" | "none"
        let rawCharCount: Int
        let extractionMs: Double
        let activeInputExcluded: Bool
    }

    func getBrowserPageText() -> PageContextResult {
        let t0 = CFAbsoluteTimeGetCurrent()
        guard let focused = getFocusedElement() else {
            return PageContextResult(text: "", source: "none", rawCharCount: 0,
                                    extractionMs: 0, activeInputExcluded: false)
        }

        // Walk up to AXWebArea or AXWindow
        var current: AXUIElement = focused
        var rootElement: AXUIElement = focused
        var rootRole = "traversal"
        var foundWebArea = false

        for _ in 0..<20 {
            var roleRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(current, kAXRoleAttribute as CFString, &roleRef) == .success,
               let role = roleRef as? String {
                if role == "AXWebArea" {
                    rootElement = current
                    rootRole = "AXWebArea"
                    foundWebArea = true
                    break
                } else if role == "AXWindow" {
                    rootElement = current
                    rootRole = "AXWindow"
                }
            }
            var parentRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(current, kAXParentAttribute as CFString, &parentRef) == .success {
                current = parentRef as! AXUIElement
            } else {
                break
            }
        }

        // Roles that are layout containers / nav chrome — expand their children but don't extract text
        let navRoles: Set<String> = [
            "AXToolbar", "AXMenuBar", "AXMenuBarItem", "AXMenu", "AXMenuItem",
            "AXPopUpButton", "AXDisclosureTriangle", "AXSplitter",
            "AXScrollBar", "AXProgressIndicator", "AXValueIndicator"
        ]
        // Roles whose children are not useful for page context
        let pruneRoles: Set<String> = [
            "AXScrollArea"  // let BFS enter but don't extract titles from it
        ]
        // Roles that contain page content text — prioritized
        let contentRoles: Set<String> = [
            "AXStaticText", "AXTextArea", "AXTextField", "AXHeading"
        ]

        let charLimit = 40_000
        let nodeLimit = 5_000
        var pieces: [String] = []
        var seenLines = Set<String>()  // dedup identical repeated nav/header text
        var queue: [AXUIElement] = [rootElement]
        var visited = 0
        var skippedInputChars = 0
        var skippedNavChars = 0

        while !queue.isEmpty && visited < nodeLimit {
            let el = queue.removeFirst()
            visited += 1

            // Skip the active input/editor to avoid self-matching
            if CFEqual(el, focused) {
                var valueRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(el, kAXValueAttribute as CFString, &valueRef) == .success,
                   let val = valueRef as? String {
                    skippedInputChars += val.count
                }
                continue
            }

            var roleRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(el, kAXRoleAttribute as CFString, &roleRef) == .success,
                  let role = roleRef as? String else { continue }

            // Skip known nav/chrome roles — extract no text, but still expand children
            let isNavRole = navRoles.contains(role)

            // Collect text value from content text roles
            if !isNavRole && contentRoles.contains(role) {
                var valueRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(el, kAXValueAttribute as CFString, &valueRef) == .success,
                   let val = valueRef as? String,
                   !val.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    // Deduplicate: skip if this exact text was already seen (catches repeated nav/header)
                    let normalized = val.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !seenLines.contains(normalized) {
                        seenLines.insert(normalized)
                        pieces.append(val)
                    }
                }
            }

            // Collect title from headings/links (not from pure nav buttons)
            let isHeadingOrLink = role == "AXHeading" || role == "AXLink"
            if !isNavRole && isHeadingOrLink {
                var titleRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(el, kAXTitleAttribute as CFString, &titleRef) == .success,
                   let title = titleRef as? String,
                   !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    let normalized = title.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !seenLines.contains(normalized) {
                        seenLines.insert(normalized)
                        pieces.append(title)
                    }
                }
            }

            // For nav roles: track skipped chars (for diagnostics) but still expand children
            if isNavRole {
                var valueRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(el, kAXValueAttribute as CFString, &valueRef) == .success,
                   let val = valueRef as? String {
                    skippedNavChars += val.count
                }
            }

            // Expand children for all non-leaf roles
            if role != "AXStaticText" {
                var childrenRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(el, kAXChildrenAttribute as CFString, &childrenRef) == .success,
                   let children = childrenRef as? [AXUIElement] {
                    queue.append(contentsOf: children)
                }
            }

            let totalSoFar = pieces.reduce(0) { $0 + $1.count }
            if totalSoFar > charLimit { break }
        }

        var raw = pieces
            .flatMap { $0.components(separatedBy: .newlines) }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        if raw.count > charLimit { raw = String(raw.prefix(charLimit)) }

        let rawDeduped = raw.count  // already deduplicated during collection
        let extractionMs = (CFAbsoluteTimeGetCurrent() - t0) * 1000.0
        let sourceLabel = foundWebArea ? "AXWebArea" : rootRole

        print("[PageContextExtractor] source=\(sourceLabel) visitedNodes=\(visited) rawChars=\(raw.count) rawCharsDeduped=\(rawDeduped) skippedInputChars=\(skippedInputChars) skippedNavChars=\(skippedNavChars) extractionMs=\(String(format: "%.1f", extractionMs)) activeInputExcluded=true")

        return PageContextResult(
            text: raw,
            source: sourceLabel,
            rawCharCount: raw.count,
            extractionMs: extractionMs,
            activeInputExcluded: true
        )
    }

    func getActiveWindowTitle() -> String? {
        guard let focused = getFocusedElement() else { return nil }
        var current: AXUIElement = focused
        for _ in 0..<15 {
            var roleRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(current, kAXRoleAttribute as CFString, &roleRef) == .success,
               let role = roleRef as? String, role == "AXWindow" {
                var titleRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(current, kAXTitleAttribute as CFString, &titleRef) == .success,
                   let title = titleRef as? String {
                    return title
                }
            }
            var parentRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(current, kAXParentAttribute as CFString, &parentRef) == .success {
                current = parentRef as! AXUIElement
            } else {
                break
            }
        }
        return nil
    }

    func getSelectedText() -> String? {
        guard let axElement = getFocusedElement() else { return nil }
        var selectedTextRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(axElement, kAXSelectedTextAttribute as CFString, &selectedTextRef) == .success,
           let selectedText = selectedTextRef as? String {
            return selectedText
        }
        return nil
    }

    /// Returns the selected text, using a Cmd+C clipboard fallback when the AX
    /// kAXSelectedTextAttribute returns empty (common in Chrome / Firefox).
    func getSelectedTextWithClipboardFallback() async -> String? {
        // 1. Try AX first (fast path)
        if let axText = getSelectedText(), !axText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            print("[TypeFlow-Debug] getSelectedText: AX succeeded — '\(axText.prefix(60))'")
            return axText
        }
        print("[TypeFlow-Debug] getSelectedText: AX returned empty — trying Cmd+C clipboard fallback")

        // 2. Save current clipboard content
        let pasteboard = NSPasteboard.general
        let savedString = pasteboard.string(forType: .string)

        // 3. Clear clipboard so we can detect a change
        pasteboard.clearContents()

        // 4. Synthesize Cmd+C
        let src = CGEventSource(stateID: .hidSystemState)
        let keyDown = CGEvent(keyboardEventSource: src, virtualKey: 8, keyDown: true) // C
        let keyUp   = CGEvent(keyboardEventSource: src, virtualKey: 8, keyDown: false)
        keyDown?.setIntegerValueField(.eventSourceUserData, value: 9999)
        keyUp?.setIntegerValueField(.eventSourceUserData, value: 9999)
        keyDown?.flags = .maskCommand
        keyUp?.flags   = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)

        // 5. Wait briefly for the app to populate the clipboard
        try? await Task.sleep(nanoseconds: 150_000_000)

        let copiedText = pasteboard.string(forType: .string)

        // 6. Restore original clipboard content
        pasteboard.clearContents()
        if let saved = savedString {
            pasteboard.setString(saved, forType: .string)
        }

        if let text = copiedText, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            print("[TypeFlow-Debug] getSelectedText: Clipboard fallback returned '\(text.prefix(60))'")
            return text
        }
        print("[TypeFlow-Debug] getSelectedText: Both AX and clipboard fallback failed")
        return nil
    }

    /// Returns the AX bounding rect of the selected text for overlay anchoring.
    /// Falls back to the caret rect if the selection rect is unavailable.
    func getSelectionRect() -> CGRect? {
        guard let axElement = getFocusedElement() else { return getCurrentCaretRect() }

        var rangeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axElement, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success,
              let rangeVal = rangeRef else { return getCurrentCaretRect() }

        var boundsRef: CFTypeRef?
        if AXUIElementCopyParameterizedAttributeValue(axElement, kAXBoundsForRangeParameterizedAttribute as CFString, rangeVal, &boundsRef) == .success,
           let boundsAX = boundsRef,
           CFGetTypeID(boundsAX) == AXValueGetTypeID() {
            let boundsVal = boundsAX as! AXValue
            var rect = CGRect.zero
            if AXValueGetValue(boundsVal, .cgRect, &rect), rect.width > 0 || rect.height > 0 {
                print("[TypeFlow-Debug] getSelectionRect: selection rect = \(rect)")
                return rect
            }
        }
        return getCurrentCaretRect()
    }


    func matchesRewriteShortcut(event: CGEvent) -> Bool {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags
        let shortcut = SettingsManager.shared.rewriteShortcut
        
        var reqOption = false
        var reqControl = false
        var reqShift = false
        var reqCommand = false
        var reqChar = ""
        
        if shortcut.contains("Option") || shortcut.contains("⌥") { reqOption = true }
        if shortcut.contains("Control") || shortcut.contains("⌃") { reqControl = true }
        if shortcut.contains("Shift") || shortcut.contains("⇧") { reqShift = true }
        if shortcut.contains("Command") || shortcut.contains("⌘") { reqCommand = true }
        
        if let last = shortcut.last {
            reqChar = String(last).uppercased()
        }
        
        let hasOption = flags.contains(.maskAlternate)
        let hasControl = flags.contains(.maskControl)
        let hasShift = flags.contains(.maskShift)
        let hasCommand = flags.contains(.maskCommand)
        
        // Safety: never match if the event carries no modifier at all
        if !hasOption && !hasControl && !hasShift && !hasCommand {
            return false
        }
        
        if reqOption != hasOption || reqControl != hasControl || reqShift != hasShift || reqCommand != hasCommand {
            return false
        }
        
        if !reqOption && !reqControl && !reqShift && !reqCommand {
            return false
        }
        
        // Fallback to keycodes for safety:
        let lowerChar = reqChar.lowercased()
        let charMap: [String: Int64] = [
            "a": 0, "b": 11, "c": 8, "d": 2, "e": 14, "f": 3, "g": 5, "h": 4, "i": 34, "j": 38,
            "k": 40, "l": 37, "m": 46, "n": 45, "o": 31, "p": 35, "q": 12, "r": 15, "s": 1, "t": 17,
            "u": 32, "v": 9, "w": 13, "x": 7, "y": 16, "z": 6
        ]
        if let mappedCode = charMap[lowerChar] {
            return keyCode == mappedCode
        }
        
        return false
    }
    
    func matchesSmartReplyShortcut(event: CGEvent) -> Bool {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags
        let shortcut = SettingsManager.shared.smartReplyShortcut
        
        var reqOption = false
        var reqControl = false
        var reqShift = false
        var reqCommand = false
        var reqChar = ""
        
        if shortcut.contains("Option") || shortcut.contains("⌥") { reqOption = true }
        if shortcut.contains("Control") || shortcut.contains("⌃") { reqControl = true }
        if shortcut.contains("Shift") || shortcut.contains("⇧") { reqShift = true }
        if shortcut.contains("Command") || shortcut.contains("⌘") { reqCommand = true }
        
        if let last = shortcut.last {
            reqChar = String(last).uppercased()
        }
        
        let hasOption = flags.contains(.maskAlternate)
        let hasControl = flags.contains(.maskControl)
        let hasShift = flags.contains(.maskShift)
        let hasCommand = flags.contains(.maskCommand)
        
        // Safety: never match if the event carries no modifier at all
        if !hasOption && !hasControl && !hasShift && !hasCommand {
            return false
        }
        
        if reqOption != hasOption || reqControl != hasControl || reqShift != hasShift || reqCommand != hasCommand {
            return false
        }
        
        if !reqOption && !reqControl && !reqShift && !reqCommand {
            return false
        }
        
        // Fallback to keycodes for safety:
        let lowerChar = reqChar.lowercased()
        let charMap: [String: Int64] = [
            "a": 0, "b": 11, "c": 8, "d": 2, "e": 14, "f": 3, "g": 5, "h": 4, "i": 34, "j": 38,
            "k": 40, "l": 37, "m": 46, "n": 45, "o": 31, "p": 35, "q": 12, "r": 15, "s": 1, "t": 17,
            "u": 32, "v": 9, "w": 13, "x": 7, "y": 16, "z": 6
        ]
        if let mappedCode = charMap[lowerChar] {
            return keyCode == mappedCode
        }
        
        return false
    }
}
