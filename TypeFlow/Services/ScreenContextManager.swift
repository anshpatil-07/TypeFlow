import Cocoa
import Vision
import ScreenCaptureKit

class ScreenContextManager {
    static let shared = ScreenContextManager()
    
    var latestScreenText: String = ""
    var previousScreenText: String = ""
    private var timer: Timer?
    
    // Evaluated at class-load time via ProcessInfo — same pattern as TypingHistoryManager.
    private static let testingMode: Bool = ProcessInfo.processInfo.arguments.contains("-runTQB")
    
    // For testing and programmatic manipulation without locking out other services
    init() {
        // Skip all TCC permission prompts during automated TQB runs.
        // TQBRunner sets latestScreenText/previousScreenText directly before each test.
        guard !ScreenContextManager.testingMode else {
            print("[TypeFlow-Debug] ScreenContextManager: TQB Test Mode - physical OCR bypassed")
            return
        }
        checkAndRequestPermission()
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
    
    func performOCROnDemand() {
        // In TQB test mode, latestScreenText is already set by the test harness.
        // Do not call the physical capture API which requires TCC permission.
        guard !ScreenContextManager.testingMode else { return }
        performOCR()
    }
    
    private func performOCR() {
        guard CGPreflightScreenCaptureAccess() else {
            print("[TypeFlow] Skipping OCR because Screen Recording permission is not granted.")
            return
        }
        
        Task {
            do {
                let content = try await SCShareableContent.current
                guard let display = content.displays.first else { return }
                
                let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
                let configuration = SCStreamConfiguration()
                configuration.width = display.width
                configuration.height = display.height
                
                let cgImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
                
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
                        self?.previousScreenText = self?.latestScreenText ?? ""
                        self?.latestScreenText = extractedText
                    }
                }
                
                // For general screen text, accurate recognition is usually better
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true
                
                let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                try handler.perform([request])
                
            } catch {
                print("Failed to perform OCR: \(error)")
            }
        }
    }
}
