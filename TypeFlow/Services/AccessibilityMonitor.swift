import Cocoa

class AccessibilityMonitor {
    var eventTap: CFMachPort?
    var runLoopSource: CFRunLoopSource?
    var onCaretMoved: ((CGRect) -> Void)?
    private var retryTimer: Timer?
    
    init(onCaretMoved: @escaping (CGRect) -> Void) {
        self.onCaretMoved = onCaretMoved
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
                    
                    if (keyCode == 48 && SettingsManager.shared.acceptShortcut == "Tab") ||
                       (keyCode == 124 && SettingsManager.shared.acceptShortcut == "Right Arrow") {
                        print("[TypeFlow] Trigger key pressed (Tab/Right)")
                        if CompletionManager.shared.handleTabPressed() {
                            print("[TypeFlow] Tab consumed by CompletionManager")
                            return nil // Consume the event
                        } else {
                            print("[TypeFlow] Tab not consumed")
                        }
                    } else {
                        // After typing, try to find the caret
                        if let monitor = refcon {
                            let unmanaged = Unmanaged<AccessibilityMonitor>.fromOpaque(monitor)
                            let obj = unmanaged.takeUnretainedValue()
                            DispatchQueue.main.async {
                                print("[TypeFlow] Checking caret rect...")
                                if let rect = obj.getCurrentCaretRect() {
                                    print("[TypeFlow] Caret rect found: \(rect)")
                                    obj.onCaretMoved?(rect)
                                    CompletionManager.shared.onTextChanged()
                                } else {
                                    print("[TypeFlow] Caret rect not found! Calling onTextChanged anyway for debugging.")
                                    // For debugging, call it anyway
                                    CompletionManager.shared.onTextChanged()
                                }
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
            print("[TypeFlow] Caret bounds failed, falling back to element bounds: pos=\(pos), size=\(size)")
            return CGRect(x: pos.x + 5, y: pos.y + 5, width: 0, height: 15)
        }
        
        return nil
    }

    func getTextBeforeCaret() -> String? {
        let systemWideElement = AXUIElementCreateSystemWide()
        var focusedElement: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(systemWideElement, kAXFocusedUIElementAttribute as CFString, &focusedElement)
        
        guard err == .success, let element = focusedElement else {
            print("[TypeFlow-Debug] AX: No focused element found")
            return nil
        }
        let axElement = element as! AXUIElement
        
        // 1. Get full text via kAXValueAttribute
        var valueRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axElement, kAXValueAttribute as CFString, &valueRef) == .success,
              let val = valueRef else {
            print("[TypeFlow-Debug] AX: kAXValueAttribute failed")
            return nil
        }
        
        var fullText: String = ""
        if let stringValue = val as? String {
            fullText = stringValue
        } else if CFGetTypeID(val) == CFAttributedStringGetTypeID() {
            let attrString = val as! CFAttributedString
            fullText = CFAttributedStringGetString(attrString) as String
        } else {
            print("[TypeFlow-Debug] AX: kAXValueAttribute returned unknown type: \(CFGetTypeID(val))")
            return nil
        }
        
        // 2. Get cursor position via kAXSelectedTextRangeAttribute
        var rangeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axElement, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success,
              let rangeVal = rangeRef else {
            print("[TypeFlow-Debug] AX: kAXSelectedTextRangeAttribute failed — returning full text suffix")
            return String(fullText.suffix(200))
        }
        
        var range = CFRange(location: 0, length: 0)
        AXValueGetValue(rangeVal as! AXValue, .cfRange, &range)
        let cursorIndex = range.location
        
        // 3. Slice text before cursor safely using UTF-16 representation
        let utf16 = fullText.utf16
        let safeCursorIndex = max(0, min(cursorIndex, utf16.count))
        
        if let sliceEnd = utf16.index(utf16.startIndex, offsetBy: safeCursorIndex, limitedBy: utf16.endIndex) {
            let textBeforeCursor = String(fullText[..<sliceEnd])
            print("[TypeFlow-Debug] AX: text before cursor (\(safeCursorIndex) UTF-16 chars): '\(textBeforeCursor.suffix(50))'")
            return String(textBeforeCursor.suffix(200))
        } else {
            let textBeforeCursor = String(fullText.prefix(safeCursorIndex))
            print("[TypeFlow-Debug] AX: text before cursor fallback: '\(textBeforeCursor.suffix(50))'")
            return String(textBeforeCursor.suffix(200))
        }
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
