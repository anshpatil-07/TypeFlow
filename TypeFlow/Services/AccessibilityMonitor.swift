import Cocoa

class AccessibilityMonitor {
    var observerTap: CFMachPort?
    var observerRunLoopSource: CFRunLoopSource?
    
    var acceptTap: CFMachPort?
    var acceptRunLoopSource: CFRunLoopSource?
    
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
    private var contextFetchWorkItem: DispatchWorkItem?
    
    private var lastDeletedWord: String?
    private var isBackspacing = false
    
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
                // Real app switch — clear buffer and completions
                print("[TypeFlow-Debug] AXObserver: focus moved to different PID (\(obj.activeFocusPID) -> \(newPID)), clearing buffer")
                obj.activeFocusPID = newPID
                DispatchQueue.main.async {
                    CompletionManager.shared.clearCompletion()
                    obj.clearKeystrokeBuffer()
                }
            } else {
                // Intra-app focus jitter (same PID)
                print("[TypeFlow-Debug] AXObserver: intra-app focus change (PID \(newPID)), clearing overlay & buffer")
                DispatchQueue.main.async {
                    CompletionManager.shared.cancelInflightTasks()
                    CompletionManager.shared.hideOverlay()
                    CompletionManager.shared.clearCompletion()
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
    
    /// Called once at launch (after 1-second delay). Retries every 2 seconds
    /// until the CGEvent tap is successfully created.
    ///
    /// WHY: AXIsProcessTrusted() is unreliable — it can return false after a
    /// fresh build even when permission IS granted in System Settings (the binary
    /// path changed so macOS revoked the cached trust). CGEvent.tapCreate is the
    /// definitive OS-level permission check: if it returns non-nil, we're trusted.
    func startWithRetry() {
        guard !isRunning else { return }
        
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
    
    private var isRunning: Bool { observerTap != nil }
    var consumedKeyCodes: Set<Int64> = []
    
    func start() {
        let eventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue) | (1 << CGEventType.leftMouseDown.rawValue) | (1 << CGEventType.rightMouseDown.rawValue)
        
        // 1. OBSERVER TAP (listenOnly): Tracks all keys asynchronously without blocking the system.
        observerTap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                if TextInjector.shared.isInjecting || event.getIntegerValueField(.eventSourceUserData) == 9999 {
                    return Unmanaged.passUnretained(event)
                }
                
                let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
                
                if let monitor = refcon {
                    let unmanaged = Unmanaged<AccessibilityMonitor>.fromOpaque(monitor)
                    let obj = unmanaged.takeUnretainedValue()
                    
                    // Mouse clicks reset state
                    if type == .leftMouseDown || type == .rightMouseDown {
                        DispatchQueue.main.async {
                            CompletionManager.shared.cancelInflightTasks()
                            CompletionManager.shared.hideOverlay()
                            CompletionManager.shared.clearCompletion()
                            obj.clearKeystrokeBuffer()
                        }
                        return Unmanaged.passUnretained(event)
                    }
                    
                    if type == .keyDown {
                        print("[TypeFlow] Observer keyDown detected: keyCode=\(keyCode)")
                        
                        // Pass event processing to the background immediately.
                        // The tap callback MUST return without blocking — copy the event
                        // and hand it off to the dedicated serial tapQueue so the CGEvent
                        // tap thread is never waiting on locks, AX IPC, or LLM state.
                        guard let asyncEvent = event.copy() else {
                            return Unmanaged.passUnretained(event)
                        }
                        
                        obj.tapQueue.async {
                            // Spacebar / Return Fast-Path
                            if keyCode == 49 || keyCode == 36 {
                                obj.handleKeystroke(keyCode: keyCode, event: asyncEvent)
                                let bufferSnapshot = obj.keystrokeBuffer
                                
                                if keyCode == 49 {
                                    if let correctionData = CompletionManager.shared.handleAsynchronousSpellcheck(bufferSnapshot: bufferSnapshot) {
                                        DispatchQueue.main.async {
                                            let exactLength = correctionData.misspelledLength + 1
                                            let delta = obj.keystrokeBuffer.count - bufferSnapshot.count
                                            
                                            guard delta >= 0 else { return }
                                            
                                            let offsetFromEnd = exactLength + delta
                                            if obj.keystrokeBuffer.count >= offsetFromEnd {
                                                let startIndex = obj.keystrokeBuffer.index(obj.keystrokeBuffer.endIndex, offsetBy: -offsetFromEnd)
                                                let endIndex = obj.keystrokeBuffer.index(startIndex, offsetBy: exactLength)
                                                obj.keystrokeBuffer.replaceSubrange(startIndex..<endIndex, with: correctionData.correction)
                                            } else {
                                                obj.clearKeystrokeBuffer()
                                            }
                                        }
                                    }
                                }
                                
                                obj.triggerContextFetch(bufferSnapshot: bufferSnapshot, delay: 0.0)
                                return
                            }
                            
                            obj.handleKeystroke(keyCode: keyCode, event: asyncEvent)
                            let bufferSnapshot = obj.keystrokeBuffer
                            let isPunctuation = (keyCode == 43 || keyCode == 47)
                            let delay = isPunctuation ? 0.0 : 0.15
                            
                            obj.triggerContextFetch(bufferSnapshot: bufferSnapshot, delay: delay)
                        }
                    }
                }
                
                return Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )
        
        // 2. ACCEPT TAP (defaultTap): Tightly scoped tap to consume specific acceptance or trigger shortcuts.
        acceptTap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                if TextInjector.shared.isInjecting || event.getIntegerValueField(.eventSourceUserData) == 9999 {
                    return Unmanaged.passRetained(event)
                }
                
                let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
                
                if let monitor = refcon {
                    let unmanaged = Unmanaged<AccessibilityMonitor>.fromOpaque(monitor)
                    let obj = unmanaged.takeUnretainedValue()
                    
                    if type == .keyDown || type == .keyUp {
                        // Rewrite Shortcut
                        if obj.matchesRewriteShortcut(event: event) {
                            if type == .keyDown {
                                print("[TypeFlow] Intercepted Rewrite Shortcut (keyDown)")
                                DispatchQueue.main.async { CompletionManager.shared.triggerRewrite() }
                            }
                            return nil
                        }
                        
                        // Smart Reply Shortcut
                        if obj.matchesSmartReplyShortcut(event: event) {
                            if type == .keyDown {
                                print("[TypeFlow] Intercepted Smart Reply Shortcut (keyDown)")
                                DispatchQueue.main.async { CompletionManager.shared.triggerSmartReply() }
                            }
                            return nil
                        }
                    }
                    
                    if type == .keyDown {
                        if keyCode == 53 { // Escape
                            if CompletionManager.shared.isRewrite || CompletionManager.shared.isSmartReply {
                                DispatchQueue.main.async { CompletionManager.shared.clearCompletion() }
                                return nil
                            }
                        }
                        
                        var tabConsumed = false
                        let isRewriteActive = CompletionManager.shared.isRewrite
                        if (keyCode == 48 && (SettingsManager.shared.acceptShortcut == "Tab" || isRewriteActive)) ||
                           (keyCode == 124 && SettingsManager.shared.acceptShortcut == "Right Arrow") {
                            if CompletionManager.shared.handleTabPressed() {
                                tabConsumed = true
                            }
                        }
                        
                        if tabConsumed {
                            obj.clearKeystrokeBuffer()
                            obj.consumedKeyCodes.insert(keyCode)
                            return nil
                        }
                        
                        if CompletionManager.shared.isRewrite || CompletionManager.shared.isSmartReply {
                            obj.consumedKeyCodes.insert(keyCode)
                            return nil
                        }
                    } else if type == .keyUp {
                        if obj.consumedKeyCodes.contains(keyCode) {
                            obj.consumedKeyCodes.remove(keyCode)
                            return nil
                        }
                    }
                }
                
                return Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )
        
        // Add BOTH taps to the run loop
        if let obsTap = observerTap {
            observerRunLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, obsTap, 0)
            CFRunLoopAddSource(CFRunLoopGetMain(), observerRunLoopSource, .commonModes)
            CGEvent.tapEnable(tap: obsTap, enable: true)
        }
        
        if let accTap = acceptTap {
            acceptRunLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, accTap, 0)
            CFRunLoopAddSource(CFRunLoopGetMain(), acceptRunLoopSource, .commonModes)
            CGEvent.tapEnable(tap: accTap, enable: true)
        }
        
        if let app = NSWorkspace.shared.frontmostApplication {
            self.setupActiveAppObserver(for: app.processIdentifier)
        }
    }
    
    private func triggerContextFetch(bufferSnapshot: String, delay: TimeInterval) {
        contextFetchWorkItem?.cancel()
        
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            // NOTE: Caret rect is intentionally NOT fetched here.
            // getCurrentCaretRect() is a heavy AX IPC call. Executing it on every
            // keystroke was causing "Significant Energy" warnings and AXTextMarker spam.
            // Caret position is now only fetched once, immediately before showing the overlay.
            DispatchQueue.main.async {
                CompletionManager.shared.onTextChanged(bufferFallback: bufferSnapshot)
            }
        }
        
        contextFetchWorkItem = workItem
        
        if delay > 0 {
            processingQueue.asyncAfter(deadline: .now() + delay, execute: workItem)
        } else {
            processingQueue.async(execute: workItem)
        }
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
    
    func getCurrentCaretRect() -> CGRect? {
        let systemWideElement = AXUIElementCreateSystemWide()
        var focusedElement: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(systemWideElement, kAXFocusedUIElementAttribute as CFString, &focusedElement)
        
        guard err == .success, let element = focusedElement else { return nil }
        let axElement = element as! AXUIElement
        

        // --- Priority: WebKit/Chromium AXTextMarker ---
        let markerRangeAttr = "AXSelectedTextMarkerRange" as CFString
        let boundsForRangeAttr = "AXBoundsForTextMarkerRange" as CFString

        var rangeValue: CFTypeRef?
        let rangeErr = AXUIElementCopyAttributeValue(axElement, markerRangeAttr, &rangeValue)

        if rangeErr == .success, let range = rangeValue {
            var boundsValue: CFTypeRef?
            let boundsErr = AXUIElementCopyParameterizedAttributeValue(axElement, boundsForRangeAttr, range, &boundsValue)
            
            if boundsErr == .success {
                // The value is an AXValue. We must decode it.
                let axValue = boundsValue as! AXValue
                var rect = CGRect.zero
                AXValueGetValue(axValue, .cgRect, &rect)
                
                if rect != .zero {
                    print("[TypeFlow-Debug] Browser Caret found via AXTextMarker: \(rect)")
                    return rect
                }
            }
        }
        print("[TypeFlow-Debug] Browser AXTextMarker extraction failed.")

        // --- Standard fallback for native macOS apps ---
        var selectedRangeRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(axElement, kAXSelectedTextRangeAttribute as CFString, &selectedRangeRef) == .success {
            let rangeValue = selectedRangeRef as! AXValue
            var range = CFRange(location: 0, length: 0)
            AXValueGetValue(rangeValue, .cfRange, &range)
            
            // Try getting the bounds of the range directly
            var bounds: CFTypeRef?
            if AXUIElementCopyParameterizedAttributeValue(axElement, kAXBoundsForRangeParameterizedAttribute as CFString, rangeValue, &bounds) == .success {
                var rect = CGRect.zero
                AXValueGetValue(bounds as! AXValue, .cgRect, &rect)
                if rect.width > 0 || rect.height > 0 {
                    return rect
                }
            }
            
            // If the range length is 0 (caret only), try to query range of length 1 around it
            if range.length == 0 {
                // Try char before caret
                if range.location > 0 {
                    var fallbackRange = CFRange(location: range.location - 1, length: 1)
                    if let fallbackValue = AXValueCreate(.cfRange, &fallbackRange) {
                        var charBounds: CFTypeRef?
                        if AXUIElementCopyParameterizedAttributeValue(axElement, kAXBoundsForRangeParameterizedAttribute as CFString, fallbackValue, &charBounds) == .success {
                            var rect = CGRect.zero
                            AXValueGetValue(charBounds as! AXValue, .cgRect, &rect)
                            if rect.width > 0 || rect.height > 0 {
                                return CGRect(x: rect.origin.x + rect.width, y: rect.origin.y, width: 0, height: rect.height)
                            }
                        }
                    }
                }
                
                // Try char at caret
                var fallbackRange = CFRange(location: range.location, length: 1)
                if let fallbackValue = AXValueCreate(.cfRange, &fallbackRange) {
                    var charBounds: CFTypeRef?
                    if AXUIElementCopyParameterizedAttributeValue(axElement, kAXBoundsForRangeParameterizedAttribute as CFString, fallbackValue, &charBounds) == .success {
                        var rect = CGRect.zero
                        AXValueGetValue(charBounds as! AXValue, .cgRect, &rect)
                        if rect.width > 0 || rect.height > 0 {
                            return CGRect(x: rect.origin.x, y: rect.origin.y, width: 0, height: rect.height)
                        }
                    }
                }
            }
        }
        
        
        // Fallback: use focused element's bottom-left corner with offset
        var positionVal: CFTypeRef?
        var sizeVal: CFTypeRef?
        if AXUIElementCopyAttributeValue(axElement, kAXPositionAttribute as CFString, &positionVal) == .success,
           AXUIElementCopyAttributeValue(axElement, kAXSizeAttribute as CFString, &sizeVal) == .success {
            var pos = CGPoint.zero
            var size = CGSize.zero
            AXValueGetValue(positionVal as! AXValue, .cgPoint, &pos)
            AXValueGetValue(sizeVal as! AXValue, .cgSize, &size)
            
            let textLength = self.keystrokeBuffer.count
            
            let estimatedTextWidth = CGFloat(textLength) * 8.0
            
            let fallbackX = pos.x + 5 + estimatedTextWidth
            let fallbackY = pos.y + max(0, size.height - 18)
            print("[TypeFlow] Caret bounds failed, falling back to element bottom-left (offset): x=\(fallbackX), y=\(fallbackY), size=\(size), textLength=\(textLength)")
            return CGRect(x: fallbackX, y: fallbackY, width: 0, height: 15)
        }
        
        return nil
    }

    private func getFocusedElement() -> AXUIElement? {
        let systemWideElement = AXUIElementCreateSystemWide()
        var focusedElement: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(systemWideElement, kAXFocusedUIElementAttribute as CFString, &focusedElement)
        guard err == .success, let element = focusedElement else { return nil }
        return (element as! AXUIElement)
    }

    func clearKeystrokeBuffer() {
        keystrokeBuffer = ""
        print("[TypeFlow-Debug] Keystroke buffer cleared")
    }
    
    private func capKeystrokeBuffer() {
        if keystrokeBuffer.count > 150 {
            keystrokeBuffer = String(keystrokeBuffer.suffix(150))
        }
    }
    
    func handleKeystroke(keyCode: Int64, event: CGEvent) {
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
            let components = keystrokeBuffer.components(separatedBy: .whitespacesAndNewlines)
            if let lastTyped = components.last, !lastTyped.isEmpty {
                let cleanWord = lastTyped.trimmingCharacters(in: .punctuationCharacters)
                if !cleanWord.isEmpty, let expansion = AdaptivePatternLearner.shared.behaviors.abbreviationExpansions[cleanWord] {
                    print("[TypeFlow-Debug] Abbreviation match: \(cleanWord) -> \(expansion)")
                    DispatchQueue.main.async {
                        TextInjector.shared.injectBackspaces(count: cleanWord.count)
                        TextInjector.shared.injectCharByChar(text: expansion)
                    }
                    if let range = keystrokeBuffer.range(of: cleanWord, options: .backwards) {
                        keystrokeBuffer.replaceSubrange(range, with: expansion)
                    }
                }
            }
            
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
                print("[TypeFlow-Debug] Backspace: buffer is now '\(keystrokeBuffer)'")
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
                print("[TypeFlow-Debug] Typed: '\(filtered)', buffer is now '\(keystrokeBuffer)'")
            }
        }
    }

    func getTextBeforeCaret() -> String? {
        guard let axElement = getFocusedElement() else {
            print("[TypeFlow-Debug] AX: No focused element found")
            if !keystrokeBuffer.isEmpty {
                print("[TypeFlow-Debug] AX: Using CGEvent keystroke buffer (no focused element): '\(keystrokeBuffer.suffix(50))'")
                return keystrokeBuffer
            }
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
                            print("[TypeFlow-Debug] AX: text extracted via kAXValue (\(safeCursorIndex) UTF-16 chars): '\(result.suffix(50))'")
                            return result
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
            print("[TypeFlow-Debug] AX: text extracted via kAXSelectedTextAttribute: '\(result.suffix(50))'")
            return result
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
                    print("[TypeFlow-Debug] AX: text extracted via kAXStringForRangeParameterizedAttribute: '\(string.suffix(50))'")
                    return string
                }
            }
        }
        
        // --- Fallback 4: CGEvent keystroke buffer ---
        if !keystrokeBuffer.isEmpty {
            print("[TypeFlow-Debug] AX: all AX queries failed. Using CGEvent keystroke buffer: '\(keystrokeBuffer.suffix(50))'")
            return keystrokeBuffer
        }
        
        print("[TypeFlow-Debug] AX: all extraction methods failed, active line is empty")
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
