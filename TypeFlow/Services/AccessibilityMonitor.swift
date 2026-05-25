import Cocoa

class AccessibilityMonitor {
    var eventTap: CFMachPort?
    var runLoopSource: CFRunLoopSource?
    var onCaretMoved: ((CGRect) -> Void)?
    private var retryTimer: Timer?
    private var keystrokeBuffer: String = ""
    
    init(onCaretMoved: @escaping (CGRect) -> Void) {
        self.onCaretMoved = onCaretMoved
        
        NotificationCenter.default.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.clearKeystrokeBuffer()
        }
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
    
    private var isRunning: Bool { eventTap != nil }
    
    func start() {
        let eventMask = (1 << CGEventType.keyDown.rawValue)
        eventTap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                if TextInjector.shared.isInjecting {
                    return Unmanaged.passRetained(event)
                }
                
                if type == .keyDown {
                    let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
                    print("[TypeFlow] keyDown detected: keyCode=\(keyCode)")
                    
                    var tabConsumed = false
                    if (keyCode == 48 && SettingsManager.shared.acceptShortcut == "Tab") ||
                       (keyCode == 124 && SettingsManager.shared.acceptShortcut == "Right Arrow") {
                        print("[TypeFlow] Trigger key pressed (Tab/Right)")
                        if CompletionManager.shared.handleTabPressed() {
                            print("[TypeFlow] Tab consumed by CompletionManager")
                            tabConsumed = true
                        } else {
                            print("[TypeFlow] Tab not consumed")
                        }
                    }
                    
                    if let monitor = refcon {
                        let unmanaged = Unmanaged<AccessibilityMonitor>.fromOpaque(monitor)
                        let obj = unmanaged.takeUnretainedValue()
                        
                        if tabConsumed {
                            obj.clearKeystrokeBuffer()
                            return nil // Consume the event
                        }
                        
                        obj.handleKeystroke(keyCode: keyCode, event: event)
                        
                        DispatchQueue.main.async {
                            print("[TypeFlow] Checking caret rect...")
                            if let rect = obj.getCurrentCaretRect() {
                                print("[TypeFlow] Caret rect found: \(rect)")
                                obj.onCaretMoved?(rect)
                                CompletionManager.shared.onTextChanged()
                            } else {
                                print("[TypeFlow] Caret rect not found! Calling onTextChanged anyway for debugging.")
                                CompletionManager.shared.onTextChanged()
                            }
                        }
                    }
                }
                return Unmanaged.passRetained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )
        
        if let tap = eventTap {
            runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
        }
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
        
        // Fallback: use focused element's position and size
        var positionVal: CFTypeRef?
        var sizeVal: CFTypeRef?
        if AXUIElementCopyAttributeValue(axElement, kAXPositionAttribute as CFString, &positionVal) == .success,
           AXUIElementCopyAttributeValue(axElement, kAXSizeAttribute as CFString, &sizeVal) == .success {
            var pos = CGPoint.zero
            var size = CGSize.zero
            AXValueGetValue(positionVal as! AXValue, .cgPoint, &pos)
            AXValueGetValue(sizeVal as! AXValue, .cgSize, &size)
            print("[TypeFlow] Caret bounds failed, falling back to element center: pos=\(pos), size=\(size)")
            return CGRect(x: pos.x + size.width / 2, y: pos.y + size.height / 2, width: 0, height: 15)
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
    
    func appendCompletionToKeystrokeBuffer(_ completion: String) {
        keystrokeBuffer += completion
        capKeystrokeBuffer()
        print("[TypeFlow-Debug] Appended completion '\(completion)' to buffer. Buffer is now '\(keystrokeBuffer)'")
    }
    
    func handleKeystroke(keyCode: Int64, event: CGEvent) {
        // Navigation / Action keys that reset the buffer
        // 36: Return, 76: Enter (numpad), 53: Escape, 48: Tab
        // 123: Left, 124: Right, 125: Down, 126: Up
        // 115: Home, 119: End, 116: PageUp, 121: PageDown
        if [36, 76, 53, 48, 123, 124, 125, 126, 115, 119, 116, 121].contains(keyCode) {
            clearKeystrokeBuffer()
            return
        }
        
        // Delete / Backspace (51)
        if keyCode == 51 {
            if !keystrokeBuffer.isEmpty {
                keystrokeBuffer.removeLast()
                print("[TypeFlow-Debug] Backspace: buffer is now '\(keystrokeBuffer)'")
            }
            return
        }
        
        // Check for modifier keys (Command/Control) that represent shortcuts
        let flags = event.flags
        if flags.contains(.maskCommand) || flags.contains(.maskControl) {
            clearKeystrokeBuffer()
            return
        }
        
        // Extract Unicode characters from the event
        if let nsEvent = NSEvent(cgEvent: event),
           let characters = nsEvent.characters,
           !characters.isEmpty {
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
                fullText = (CFAttributedStringGetString(val as! CFAttributedString) as String)
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
                        let result = String(textBeforeCursor.suffix(200))
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
            let result = String(selectedText.suffix(200))
            print("[TypeFlow-Debug] AX: text extracted via kAXSelectedTextAttribute: '\(result.suffix(50))'")
            return result
        }
        
        // --- Fallback 3: kAXStringForRangeParameterizedAttribute ---
        var selectedRangeRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(axElement, kAXSelectedTextRangeAttribute as CFString, &selectedRangeRef) == .success,
           let rangeValue = selectedRangeRef {
            var range = CFRange(location: 0, length: 0)
            AXValueGetValue(rangeValue as! AXValue, .cfRange, &range)
            
            let length = min(200, range.location)
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
}
