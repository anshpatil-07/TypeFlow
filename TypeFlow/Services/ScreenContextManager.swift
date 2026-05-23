import Cocoa
import Vision

class ScreenContextManager {
    static let shared = ScreenContextManager()
    
    private(set) var latestScreenText: String = ""
    private var timer: Timer?
    private let queue = DispatchQueue(label: "com.cotyper.ScreenContextManager", qos: .background)
    
    private init() {
        start()
    }
    
    func start() {
        checkAndRequestPermission()
        
        // Run OCR every 5 seconds
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.performOCR()
        }
        // Run immediately once
        performOCR()
    }
    
    func checkAndRequestPermission() {
        if !CGPreflightScreenCaptureAccess() {
            print("[TypeFlow] Requesting Screen Recording permission...")
            CGRequestScreenCaptureAccess()
        } else {
            print("[TypeFlow] Screen Recording permission is already granted.")
        }
    }
    
    func stop() {
        timer?.invalidate()
        timer = nil
    }
    
    private func performOCR() {
        guard CGPreflightScreenCaptureAccess() else {
            print("[TypeFlow] Skipping OCR because Screen Recording permission is not granted.")
            return
        }
        
        queue.async {
            guard let screen = NSScreen.main else { return }
            
            let rect = screen.frame
            // To capture the screen, we use CGWindowListCreateImage
            guard let cgImage = CGWindowListCreateImage(
                rect,
                .optionOnScreenOnly,
                kCGNullWindowID,
                .nominalResolution
            ) else { return }
            
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
            do {
                try handler.perform([request])
            } catch {
                print("Failed to perform OCR: \(error)")
            }
        }
    }
}
