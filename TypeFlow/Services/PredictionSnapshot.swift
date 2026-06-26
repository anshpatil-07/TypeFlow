import Foundation

struct PredictionSnapshot: Sendable, Identifiable {
    var id: UInt64 { generationID }
    
    let generationID: UInt64
    let textBeforeCaret: String
    let liveBuffer: String // To extract typed characters effectively
    let isPunctuation: Bool
    
    // Timing instrumentation
    let creationTime: CFAbsoluteTime
}

struct GenerationMetrics: Sendable {
    let generationID: UInt64
    var snapshotCreationTime: CFAbsoluteTime = 0
    var promptBuildStartTime: CFAbsoluteTime = 0
    var promptBuildEndTime: CFAbsoluteTime = 0
    var inferenceStartTime: CFAbsoluteTime = 0
    var firstTokenTime: CFAbsoluteTime? = nil
    var inferenceEndTime: CFAbsoluteTime = 0
    var sanitizationStartTime: CFAbsoluteTime = 0
    var sanitizationEndTime: CFAbsoluteTime = 0
    var overlaySwapTime: CFAbsoluteTime = 0
    
    func printReport() {
        let queueWait = (promptBuildStartTime - snapshotCreationTime) * 1000
        let promptBuild = (promptBuildEndTime - promptBuildStartTime) * 1000
        let preInferenceWait = (inferenceStartTime - promptBuildEndTime) * 1000
        
        let ttft: Double
        if let first = firstTokenTime {
            ttft = (first - inferenceStartTime) * 1000
        } else {
            ttft = -1
        }
        
        let genTime = (inferenceEndTime - inferenceStartTime) * 1000
        let sanitization = (sanitizationEndTime - sanitizationStartTime) * 1000
        let overlayWait = (overlaySwapTime - sanitizationEndTime) * 1000
        let total = (overlaySwapTime - snapshotCreationTime) * 1000
        
        print("""
        [TypeFlow-Latency] Generation #\(generationID) Pipeline Report:
          - Queue wait:      \(String(format: "%.2f", queueWait)) ms
          - Prompt build:    \(String(format: "%.2f", promptBuild)) ms
          - Pre-infer wait:  \(String(format: "%.2f", preInferenceWait)) ms
          - TTFT:            \(ttft >= 0 ? String(format: "%.2f", ttft) : "N/A") ms
          - Inference total: \(String(format: "%.2f", genTime)) ms
          - Sanitization:    \(String(format: "%.2f", sanitization)) ms
          - Swap delay:      \(String(format: "%.2f", overlayWait)) ms
          ===============================
          - TOTAL LATENCY:   \(String(format: "%.2f", total)) ms
        """)
    }
}
