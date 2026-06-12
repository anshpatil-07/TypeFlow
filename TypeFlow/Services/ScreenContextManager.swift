import Cocoa
import Vision
import ScreenCaptureKit

class ScreenContextManager {
    static let shared = ScreenContextManager()
    
    private(set) var latestScreenText: String = ""
    private var timer: Timer?
    
    private init() {
        checkAndRequestPermission()
    }
    
    func checkAndRequestPermission() {
        if !CGPreflightScreenCaptureAccess() {
            print("[TypeFlow] Requesting Screen Recording permission...")
            CGRequestScreenCaptureAccess()
        } else {
            print("[TypeFlow] Screen Recording permission is already granted.")
        }
    }
    
    func performOCROnDemand() {
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
