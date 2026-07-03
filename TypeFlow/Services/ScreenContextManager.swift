import Cocoa
import Vision
import ScreenCaptureKit

class ScreenContextManager {
    static let shared = ScreenContextManager()
    
    var latestScreenText: String = ""
    private var timer: Timer?
    
    static var lastPID: pid_t? = nil
    static var lastWindowTitle: String? = nil
    
    // Evaluated at class-load time via ProcessInfo and file trigger — same pattern as TypingHistoryManager.
    static let testingMode: Bool = FileManager.default.fileExists(atPath: "/tmp/typeflow_tqb_active") || ProcessInfo.processInfo.arguments.contains("-runTQB")
    
    init() {
        if ScreenContextManager.testingMode {
            print("[TypeFlow-Debug] ScreenContextManager: TQB Test Mode - physical OCR bypassed")
        }
        
        // Start background timer to refresh screen context cache every 5 seconds off the typing hot path.
        DispatchQueue.main.async {
            self.timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
                guard let self = self else { return }
                if !InputCriticalSection.shared.isActive {
                    let monitor = CompletionManager.shared.accessibilityMonitor
                    Task {
                        await self.refreshScreenContextCache(accessibilityMonitor: monitor)
                    }
                }
            }
        }
    }

    
    func checkAndRequestPermission() {
        if !CGPreflightScreenCaptureAccess() {
            print("[TypeFlow] Requesting Screen Recording permission...")
            CGRequestScreenCaptureAccess()
            
            // Fallback: Trigger immediately via SCShareableContent
            Task {
                do {
                    _ = try await SCShareableContent.current
                } catch {}
            }
            
            if UserDefaults.standard.bool(forKey: "runTQB") || CommandLine.arguments.contains("-runTQB") {
                print("[TypeFlow-Fatal] Screen Recording Permission Denied - OCR tests will fail")
            }
        } else {
            print("[TypeFlow] Screen Recording permission is already granted.")
        }
    }
    
    struct ScreenContextCache {
        let text: String
        let source: String   // "AXWebArea" | "AXWindow" | "traversal" | "OCR" | "focusedAX" | "none"
        let timestamp: Date
        let pageHash: Int    // hash of the extracted text to detect page changes
        let rawCharCount: Int
        let extractionMs: Double
    }
    
    var cachedContext: ScreenContextCache?

    // Dedup: avoid re-running expensive extraction when the page content hash is unchanged.
    private var lastExtractionHash: Int = 0
    
    /// Refresh the page context cache using full AXWebArea traversal (primary) or OCR (fallback).
    /// MUST be called off the keystroke hot path — only on focus change, idle, or page-change.
    func refreshScreenContextCache(accessibilityMonitor: AccessibilityMonitor?) async {
        guard !ScreenContextManager.testingMode else { return }

        let t0 = CFAbsoluteTimeGetCurrent()
        var text = ""
        var source = "none"
        var rawCharCount = 0
        var extractionMs = 0.0

        // 1. Try full AXWebArea/AXWindow BFS traversal (primary method)
        if let monitor = accessibilityMonitor {
            let result = monitor.getBrowserPageText()
            if !result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                text = result.text
                source = result.source   // "AXWebArea" | "AXWindow" | "traversal"
                rawCharCount = result.rawCharCount
                extractionMs = result.extractionMs
            }
        }

        // 2. If BFS yielded nothing, try the focused field's full text as context (focusedAX)
        if text.isEmpty, let monitor = accessibilityMonitor {
            if let fieldText = monitor.getFullFieldText(),
               !fieldText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                text = fieldText
                source = "focusedAX"
                rawCharCount = text.count
                extractionMs = (CFAbsoluteTimeGetCurrent() - t0) * 1000.0
            }
        }

        // 3. OCR fallback when AX extraction gave nothing
        if text.isEmpty {
            await performOCR()
            if !latestScreenText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                text = latestScreenText
                source = "OCR"
                rawCharCount = text.count
                extractionMs = (CFAbsoluteTimeGetCurrent() - t0) * 1000.0
            }
        }

        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            print("[ScreenContextManager] refresh: no context available source=none")
            return
        }

        // Dedup: skip cache update if page text content hash unchanged
        let newHash = text.hashValue
        if newHash == lastExtractionHash, let existing = cachedContext {
            let ageMs = Date().timeIntervalSince(existing.timestamp) * 1000.0
            print("[ScreenContextManager] refresh: unchanged hash=\(newHash) cacheAgeMs=\(String(format: "%.0f", ageMs)) — skipping update")
            return
        }

        lastExtractionHash = newHash
        let totalMs = (CFAbsoluteTimeGetCurrent() - t0) * 1000.0
        cachedContext = ScreenContextCache(
            text: text,
            source: source,
            timestamp: Date(),
            pageHash: newHash,
            rawCharCount: rawCharCount,
            extractionMs: extractionMs
        )
        print("[ScreenContextManager] refreshed source=\(source) rawChars=\(rawCharCount) totalMs=\(String(format: "%.1f", totalMs))")
    }
    
    func performOCROnDemand() async {
        guard !ScreenContextManager.testingMode else { return }
        await performOCR()
    }
    
    private func performOCR() async {
        guard CGPreflightScreenCaptureAccess() else {
            print("[TypeFlow] Skipping OCR because Screen Recording permission is not granted.")
            return
        }
        
        do {
            let app = NSWorkspace.shared.frontmostApplication
            let isBrowser = ["zen", "safari", "chrome", "brave", "edge", "arc", "firefox"].contains {
                app?.localizedName?.lowercased().contains($0) == true ||
                app?.bundleIdentifier?.lowercased().contains($0) == true
            }
            
            var cgImage: CGImage?
            
            if isBrowser {
                if let windowID = self.getActiveBrowserWindowID(for: app) {
                    cgImage = CGWindowListCreateImage(.null, .optionIncludingWindow, windowID, .boundsIgnoreFraming)
                }
            }
            
            if cgImage == nil {
                let content = try await SCShareableContent.current
                guard let display = content.displays.first else { return }
                let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
                let configuration = SCStreamConfiguration()
                configuration.width = display.width
                configuration.height = display.height
                cgImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
            }
            
            guard let finalImage = cgImage else { return }
            
            let request = VNRecognizeTextRequest { [weak self] request, error in
                guard let observations = request.results as? [VNRecognizedTextObservation] else { return }
                
                var extractedText = ""
                for observation in observations {
                    guard let topCandidate = observation.topCandidates(1).first else { continue }
                    extractedText += topCandidate.string + "\n"
                }
                
                // Truncate to 2000 characters
                if extractedText.count > 2000 {
                    extractedText = String(extractedText.prefix(2000)) + "..."
                }
                
                DispatchQueue.main.async {
                    self?.latestScreenText = extractedText
                }
            }
            
            // For general screen text, accurate recognition is usually better
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            
            let handler = VNImageRequestHandler(cgImage: finalImage, options: [:])
            try handler.perform([request])
            
        } catch {
            print("Failed to perform OCR: \(error)")
        }
    }
    
    func performRapidBrowserOCR() async -> String? {
        guard !ScreenContextManager.testingMode else { return nil }
        
        let app = NSWorkspace.shared.frontmostApplication
        let isBrowser = ["zen", "safari", "chrome", "brave", "edge", "arc", "firefox"].contains {
            app?.localizedName?.lowercased().contains($0) == true ||
            app?.bundleIdentifier?.lowercased().contains($0) == true
        }
        guard isBrowser else { return nil }
        

        
        guard let windowID = self.getActiveBrowserWindowID(for: app) else { return nil }
        guard let cgImage = CGWindowListCreateImage(.null, .optionIncludingWindow, windowID, .boundsIgnoreFraming) else { return nil }
        
        return await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: nil)
                    return
                }
                
                var extractedText = ""
                for observation in observations {
                    guard let topCandidate = observation.topCandidates(1).first else { continue }
                    extractedText += topCandidate.string + "\n"
                }
                
                if extractedText.count > 2000 {
                    extractedText = String(extractedText.prefix(2000)) + "..."
                }
                
                continuation.resume(returning: extractedText.isEmpty ? nil : extractedText)
            }
            
            request.recognitionLevel = .fast
            request.usesLanguageCorrection = false
            
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(returning: nil)
            }
        }
    }
    
    private func getActiveBrowserWindowID(for app: NSRunningApplication?) -> CGWindowID? {
        guard let app = app else { return nil }
        let pid = app.processIdentifier
        let appElement = AXUIElementCreateApplication(pid)
        var windowRef: CFTypeRef?
        
        if AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &windowRef) != .success {
            AXUIElementCopyAttributeValue(appElement, kAXMainWindowAttribute as CFString, &windowRef)
        }
        
        guard let activeWindow = windowRef else { return nil }
        
        var titleRef: CFTypeRef?
        var axTitle: String? = nil
        if AXUIElementCopyAttributeValue(activeWindow as! AXUIElement, kAXTitleAttribute as CFString, &titleRef) == .success {
            axTitle = titleRef as? String
        }
        
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        var axBounds: CGRect? = nil
        
        if AXUIElementCopyAttributeValue(activeWindow as! AXUIElement, kAXPositionAttribute as CFString, &posRef) == .success,
           AXUIElementCopyAttributeValue(activeWindow as! AXUIElement, kAXSizeAttribute as CFString, &sizeRef) == .success {
            var position = CGPoint.zero
            var size = CGSize.zero
            AXValueGetValue(posRef as! AXValue, .cgPoint, &position)
            AXValueGetValue(sizeRef as! AXValue, .cgSize, &size)
            axBounds = CGRect(origin: position, size: size)
        }
        
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windowListInfo = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return nil }
        
        for windowInfo in windowListInfo {
            if (windowInfo[kCGWindowOwnerPID as String] as? Int32) == pid && (windowInfo[kCGWindowLayer as String] as? Int) == 0 {
                
                let cgTitle = windowInfo[kCGWindowName as String] as? String
                var boundsMatch = false
                
                if let boundsDict = windowInfo[kCGWindowBounds as String] as? [String: Any],
                   let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary),
                   let expectedBounds = axBounds {
                    
                    if abs(bounds.origin.x - expectedBounds.origin.x) < 5 &&
                       abs(bounds.origin.y - expectedBounds.origin.y) < 5 &&
                       abs(bounds.width - expectedBounds.width) < 5 &&
                       abs(bounds.height - expectedBounds.height) < 5 {
                        boundsMatch = true
                    }
                }
                
                let titleMatch = (axTitle != nil && !axTitle!.isEmpty && cgTitle == axTitle)
                
                if boundsMatch || titleMatch {
                    if let windowID = windowInfo[kCGWindowNumber as String] as? CGWindowID {
                        return windowID
                    }
                }
            }
        }
        
        if let frontWindow = windowListInfo.first(where: { ($0[kCGWindowOwnerPID as String] as? Int32) == pid && ($0[kCGWindowLayer as String] as? Int) == 0 }) {
            return frontWindow[kCGWindowNumber as String] as? CGWindowID
        }
        
        return nil
    }
}
