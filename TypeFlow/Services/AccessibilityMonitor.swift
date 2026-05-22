import Cocoa

class AccessibilityMonitor {
    var eventTap: CFMachPort?
    var runLoopSource: CFRunLoopSource?
    var onCaretMoved: ((CGRect) -> Void)?
    
    init(onCaretMoved: @escaping (CGRect) -> Void) {
        self.onCaretMoved = onCaretMoved
    }
    
    func start() {
        if !AXIsProcessTrusted() {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
            AXIsProcessTrustedWithOptions(options as CFDictionary)
            print("Requesting Accessibility Permissions")
            return
        }
        
        let eventMask = (1 << CGEventType.keyDown.rawValue)
        eventTap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                if type == .keyDown {
                    let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
                    if (keyCode == 48 && SettingsManager.shared.acceptShortcut == "Tab") ||
                       (keyCode == 124 && SettingsManager.shared.acceptShortcut == "Right Arrow") {
                        if CompletionManager.shared.handleTabPressed() {
                            return nil // Consume the event
                        }
                    } else {
                        // After typing, try to find the caret
                        if let monitor = refcon {
                            let unmanaged = Unmanaged<AccessibilityMonitor>.fromOpaque(monitor)
                            let obj = unmanaged.takeUnretainedValue()
                            DispatchQueue.main.async {
                                if let rect = obj.getCurrentCaretRect() {
                                    obj.onCaretMoved?(rect)
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
            CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
        }
    }
    
    func getCurrentCaretRect() -> CGRect? {
        let systemWideElement = AXUIElementCreateSystemWide()
        var focusedElement: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(systemWideElement, kAXFocusedUIElementAttribute as CFString, &focusedElement)
        
        if err == .success, let element = focusedElement {
            let axElement = element as! AXUIElement
            var selectedRange: CFTypeRef?
            if AXUIElementCopyAttributeValue(axElement, kAXSelectedTextRangeAttribute as CFString, &selectedRange) == .success {
                let range = selectedRange as! AXValue
                var bounds: CFTypeRef?
                if AXUIElementCopyParameterizedAttributeValue(axElement, kAXBoundsForRangeParameterizedAttribute as CFString, range, &bounds) == .success {
                    var rect = CGRect.zero
                    AXValueGetValue(bounds as! AXValue, .cgRect, &rect)
                    return rect
                }
            }
        }
        return nil
    }

    func getTextBeforeCaret() -> String? {
        let systemWideElement = AXUIElementCreateSystemWide()
        var focusedElement: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(systemWideElement, kAXFocusedUIElementAttribute as CFString, &focusedElement)
        
        if err == .success, let element = focusedElement {
            let axElement = element as! AXUIElement
            var selectedRangeRef: CFTypeRef?
            
            if AXUIElementCopyAttributeValue(axElement, kAXSelectedTextRangeAttribute as CFString, &selectedRangeRef) == .success {
                let rangeValue = selectedRangeRef as! AXValue
                var range = CFRange(location: 0, length: 0)
                AXValueGetValue(rangeValue, .cfRange, &range)
                
                // Get up to 200 characters before the caret
                let length = min(200, range.location)
                let startLocation = range.location - length
                let fetchRange = CFRange(location: startLocation, length: length)
                
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
    
    func getFullFieldText() -> String? {
        let systemWideElement = AXUIElementCreateSystemWide()
        var focusedElement: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(systemWideElement, kAXFocusedUIElementAttribute as CFString, &focusedElement)
        
        if err == .success, let element = focusedElement {
            let axElement = element as! AXUIElement
            
            // Try to get the entire value first
            var valueRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(axElement, kAXValueAttribute as CFString, &valueRef) == .success {
                if let stringValue = valueRef as? String {
                    // Truncate if too long (e.g. 4000 chars)
                    if stringValue.count > 4000 {
                        return "..." + String(stringValue.suffix(4000))
                    }
                    return stringValue
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
