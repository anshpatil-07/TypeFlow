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
                    if keyCode == 48 { // Tab
                        print("Tab pressed")
                    } else {
                        // After typing, try to find the caret
                        if let monitor = refcon {
                            let unmanaged = Unmanaged<AccessibilityMonitor>.fromOpaque(monitor)
                            let obj = unmanaged.takeUnretainedValue()
                            DispatchQueue.main.async {
                                if let rect = obj.getCurrentCaretRect() {
                                    obj.onCaretMoved?(rect)
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
}
