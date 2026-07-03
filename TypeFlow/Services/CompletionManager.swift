import Cocoa

final class LatencyInstrumentation: @unchecked Sendable {
    static let shared = LatencyInstrumentation()

    private struct Metrics {
        var requestID: UInt64?
        var workID: UInt64
        var inputEventTime: CFAbsoluteTime?
        var onTextChangedTime: CFAbsoluteTime?
        var debounceScheduledTime: CFAbsoluteTime?
        var debounceFiredTime: CFAbsoluteTime?
        var generationRequestedTime: CFAbsoluteTime?
        var contextStartTime: CFAbsoluteTime?
        var contextEndTime: CFAbsoluteTime?
        var axStartTime: CFAbsoluteTime?
        var axEndTime: CFAbsoluteTime?
        var ocrStartTime: CFAbsoluteTime?
        var ocrEndTime: CFAbsoluteTime?
        var promptStartTime: CFAbsoluteTime?
        var promptEndTime: CFAbsoluteTime?
        var llamaStartTime: CFAbsoluteTime?
        var firstTokenTime: CFAbsoluteTime?
        var firstUsableTime: CFAbsoluteTime?
        var renderRequestedTime: CFAbsoluteTime?
        var renderAppliedTime: CFAbsoluteTime?
        var cancellationRequestedTime: CFAbsoluteTime?
        var startTime: CFAbsoluteTime?
        
        var tokenizationStartTime: CFAbsoluteTime?
        var tokenizationEndTime: CFAbsoluteTime?
        var generationEndTime: CFAbsoluteTime?
        
        var debounceDelayMs: Int?
        var promptTokenCount: Int?
        var generatedTokenCount: Int?
        
        var boundedPrefixLen: Int?
        var boundedPrefixLineCount: Int?
        var suffixLen: Int?
        var prefixWasTruncated: Bool?
        var trailingSpacePreserved: Bool?
        
        var promptMode: String?
        var modelProfile: String?
        var completionKind: String?
        var activeLine: String?
        var finalSuggestion: String?
        var visibleApplied: Bool = false
        var rejectReason: String?
        
        var cancelledSummaryLogged = false
        var successSummaryLogged = false
        var abortedByStage1B = false
    }

    private let lock = NSLock()
    private var latestInputTime: CFAbsoluteTime?
    private var latestContextStartTime: CFAbsoluteTime?
    private var latestContextEndTime: CFAbsoluteTime?
    private var latestOnTextChangedTime: CFAbsoluteTime?
    private var latestDebouncedWorkID: UInt64?
    private var metricsByWorkID: [UInt64: Metrics] = [:]
    private var workIDByRequestID: [UInt64: UInt64] = [:]

    private func now() -> CFAbsoluteTime { CFAbsoluteTimeGetCurrent() }

    private func idString(_ value: UInt64?) -> String {
        guard let value else { return "nil" }
        return String(value)
    }

    private func ms(_ start: CFAbsoluteTime?, _ end: CFAbsoluteTime?) -> String {
        guard let start, let end else { return "nil" }
        return String(format: "%.1f", (end - start) * 1000.0)
    }

    private func log(_ message: String) {
        print("[Latency] \(message)")
    }

    func recordInputEvent(bufferLen: Int, delay: TimeInterval) -> CFAbsoluteTime {
        let t = now()
        lock.lock()
        latestInputTime = t
        lock.unlock()
        log("input event bufferLen=\(bufferLen) contextDelayMs=\(String(format: "%.1f", delay * 1000.0))")
        return t
    }

    func contextFetchStart(inputTime: CFAbsoluteTime?, bufferLen: Int) {
        let t = now()
        lock.lock()
        latestInputTime = inputTime ?? latestInputTime ?? t
        latestContextStartTime = t
        lock.unlock()
        log("context fetch start bufferLen=\(bufferLen)")
    }

    func contextFetchEnd(bufferLen: Int) {
        let t = now()
        lock.lock()
        latestContextEndTime = t
        if let workID = latestDebouncedWorkID {
            var metrics = metricsByWorkID[workID] ?? Metrics(workID: workID)
            metrics.contextEndTime = t
            metricsByWorkID[workID] = metrics
        }
        lock.unlock()
        log("context fetch end bufferLen=\(bufferLen)")
    }

    func onTextChanged(bufferLen: Int) {
        let t = now()
        lock.lock()
        latestInputTime = latestInputTime ?? t
        latestOnTextChangedTime = t
        lock.unlock()
        log("onTextChanged bufferLen=\(bufferLen)")
    }

    func debounceScheduled(workID: UInt64, delayMs: Int) {
        let t = now()
        lock.lock()
        var metrics = metricsByWorkID[workID] ?? Metrics(workID: workID)
        metrics.inputEventTime = latestInputTime
        metrics.contextStartTime = latestContextStartTime
        metrics.contextEndTime = latestContextEndTime.flatMap { endTime in
            guard let startTime = latestContextStartTime, endTime >= startTime else { return nil }
            return endTime
        }
        metrics.onTextChangedTime = latestOnTextChangedTime ?? t
        metrics.debounceScheduledTime = t
        metrics.debounceDelayMs = delayMs
        latestDebouncedWorkID = workID
        metricsByWorkID[workID] = metrics
        lock.unlock()
        log("debounce scheduled workID=\(workID) delayMs=\(delayMs)")
    }

    func debounceFired(workID: UInt64) {
        let t = now()
        lock.lock()
        var metrics = metricsByWorkID[workID] ?? Metrics(workID: workID)
        metrics.debounceFiredTime = t
        metricsByWorkID[workID] = metrics
        lock.unlock()
        log("debounce fired workID=\(workID)")
    }

    func generationRequested(workID: UInt64?) {
        let t = now()
        guard let workID else {
            log("generation requested workID=nil")
            return
        }
        lock.lock()
        var metrics = metricsByWorkID[workID] ?? Metrics(workID: workID)
        metrics.generationRequestedTime = t
        metricsByWorkID[workID] = metrics
        lock.unlock()
        log("generation requested workID=\(workID)")
    }

    func axFetchStart(workID: UInt64?) {
        let t = now()
        if let workID {
            lock.lock()
            var metrics = metricsByWorkID[workID] ?? Metrics(workID: workID)
            metrics.axStartTime = t
            metricsByWorkID[workID] = metrics
            lock.unlock()
        }
        log("AX fetch start workID=\(idString(workID))")
    }

    func axFetchEnd(workID: UInt64?, source: String, textLen: Int) {
        let t = now()
        if let workID {
            lock.lock()
            var metrics = metricsByWorkID[workID] ?? Metrics(workID: workID)
            metrics.axEndTime = t
            metricsByWorkID[workID] = metrics
            lock.unlock()
        }
        log("AX fetch end workID=\(idString(workID)) source=\(source) textLen=\(textLen)")
    }

    func ocrStart(workID: UInt64?) {
        let t = now()
        if let workID {
            lock.lock()
            var metrics = metricsByWorkID[workID] ?? Metrics(workID: workID)
            metrics.ocrStartTime = t
            metricsByWorkID[workID] = metrics
            lock.unlock()
        }
        log("OCR/context extras start workID=\(idString(workID))")
    }

    func ocrEnd(workID: UInt64?, textLen: Int) {
        let t = now()
        if let workID {
            lock.lock()
            var metrics = metricsByWorkID[workID] ?? Metrics(workID: workID)
            metrics.ocrEndTime = t
            metricsByWorkID[workID] = metrics
            lock.unlock()
        }
        log("OCR/context extras end workID=\(idString(workID)) textLen=\(textLen)")
    }

    func requestStarted(requestID: UInt64, workID: UInt64) {
        let t = now()
        lock.lock()
        var metrics = metricsByWorkID[workID] ?? Metrics(workID: workID)
        metrics.requestID = requestID
        metrics.startTime = metrics.startTime ?? t
        workIDByRequestID[requestID] = workID
        metricsByWorkID[workID] = metrics
        lock.unlock()
        log("request started requestID=\(requestID) workID=\(workID)")
    }

    func promptBuildStart(requestID: UInt64?, workID: UInt64?) {
        let t = now()
        guard let workID else {
            log("prompt build start requestID=\(idString(requestID)) workID=nil")
            return
        }
        lock.lock()
        var metrics = metricsByWorkID[workID] ?? Metrics(workID: workID)
        metrics.promptStartTime = t
        metricsByWorkID[workID] = metrics
        lock.unlock()
        log("prompt build start requestID=\(idString(requestID)) workID=\(workID)")
    }

    func promptBuildEnd(requestID: UInt64?, workID: UInt64?) {
        let t = now()
        if let workID {
            lock.lock()
            var metrics = metricsByWorkID[workID] ?? Metrics(workID: workID)
            metrics.promptEndTime = t
            metricsByWorkID[workID] = metrics
            lock.unlock()
        }
        log("prompt build end requestID=\(idString(requestID)) workID=\(idString(workID))")
    }

    func llamaGenerationStart(requestID: UInt64?, workID: UInt64?) {
        let t = now()
        if let workID {
            lock.lock()
            var metrics = metricsByWorkID[workID] ?? Metrics(workID: workID)
            metrics.llamaStartTime = t
            metricsByWorkID[workID] = metrics
            lock.unlock()
        }
        log("llama generation start requestID=\(idString(requestID)) workID=\(idString(workID))")
    }

    func firstToken(requestID: UInt64?, workID: UInt64?) {
        let t = now()
        guard let workID else { return }
        lock.lock()
        var metrics = metricsByWorkID[workID] ?? Metrics(workID: workID)
        let shouldLog = metrics.firstTokenTime == nil
        if shouldLog {
            metrics.firstTokenTime = t
            metricsByWorkID[workID] = metrics
        }
        lock.unlock()
        if shouldLog {
            log("first token requestID=\(idString(requestID)) workID=\(workID)")
        }
    }

    func firstUsable(requestID: UInt64, workID: UInt64, textLen: Int) {
        let t = now()
        lock.lock()
        var metrics = metricsByWorkID[workID] ?? Metrics(workID: workID)
        let shouldLog = metrics.firstUsableTime == nil
        if shouldLog {
            metrics.firstUsableTime = t
            metricsByWorkID[workID] = metrics
        }
        lock.unlock()
        if shouldLog {
            log("first usable completion requestID=\(requestID) workID=\(workID) textLen=\(textLen)")
            print("[RenderSchedule] firstUsableCompletion requestID=\(requestID) t=\(String(format: "%.6f", t))")
        }
    }

    func renderRequested(requestID: UInt64, workID: UInt64, source: String, textLen: Int) {
        let t = now()
        lock.lock()
        var metrics = metricsByWorkID[workID] ?? Metrics(workID: workID)
        metrics.renderRequestedTime = t
        metricsByWorkID[workID] = metrics
        lock.unlock()
        log("overlay render requested requestID=\(requestID) workID=\(workID) source=\(source) textLen=\(textLen)")
    }

    func renderApplied(requestID: UInt64? = nil, textLen: Int, source: String) {
        let t = now()
        var summary: String?
        lock.lock()
        if let requestID = requestID,
           let workID = workIDByRequestID[requestID],
           var metrics = metricsByWorkID[workID] {
            if metrics.renderAppliedTime == nil {
                metrics.renderAppliedTime = t
                metrics.visibleApplied = true
                metricsByWorkID[workID] = metrics
                summary = successSummary(for: metrics)
                if let renderRequestedTime = metrics.renderRequestedTime {
                    let renderMs = (t - renderRequestedTime) * 1000.0
                    print("[RenderSchedule] renderMsAttributed requestID=\(requestID) renderMs=\(String(format: "%.1f", renderMs))")
                }
            }
        }
        lock.unlock()
        log("overlay render applied source=\(source) textLen=\(textLen)")
        if let summary { print(summary) }
    }

    func setPromptMetrics(requestID: UInt64?, workID: UInt64, boundedLen: Int, lineCount: Int, suffixLen: Int, truncated: Bool, trailingPreserved: Bool, mode: String) {
        lock.lock()
        var metrics = metricsByWorkID[workID] ?? Metrics(workID: workID)
        metrics.boundedPrefixLen = boundedLen
        metrics.boundedPrefixLineCount = lineCount
        metrics.suffixLen = suffixLen
        metrics.prefixWasTruncated = truncated
        metrics.trailingSpacePreserved = trailingPreserved
        metrics.promptMode = mode
        metricsByWorkID[workID] = metrics
        lock.unlock()
    }
    
    func setClassification(requestID: UInt64?, workID: UInt64, profile: String, kind: String, activeLine: String, finalSuggestion: String) {
        lock.lock()
        var metrics = metricsByWorkID[workID] ?? Metrics(workID: workID)
        metrics.modelProfile = profile
        metrics.completionKind = kind
        metrics.activeLine = activeLine
        metrics.finalSuggestion = finalSuggestion
        metricsByWorkID[workID] = metrics
        lock.unlock()
    }
    
    func setTokenizationMetrics(requestID: UInt64?, workID: UInt64, promptTokens: Int, generatedTokens: Int, tStart: CFAbsoluteTime?, tEnd: CFAbsoluteTime?, gEnd: CFAbsoluteTime?) {
        lock.lock()
        var metrics = metricsByWorkID[workID] ?? Metrics(workID: workID)
        if let pt = promptTokens as Int? { metrics.promptTokenCount = pt }
        if let gt = generatedTokens as Int? { metrics.generatedTokenCount = gt }
        if let ts = tStart { metrics.tokenizationStartTime = ts }
        if let te = tEnd { metrics.tokenizationEndTime = te }
        if let ge = gEnd { metrics.generationEndTime = ge }
        metricsByWorkID[workID] = metrics
        lock.unlock()
    }



    func renderExcluded(requestID: UInt64, reason: String) {
        lock.lock()
        if let workID = workIDByRequestID[requestID],
           var metrics = metricsByWorkID[workID],
           metrics.renderAppliedTime == nil {
            metrics.renderRequestedTime = nil
            metrics.rejectReason = reason
            metrics.visibleApplied = false
            metricsByWorkID[workID] = metrics
        }
        lock.unlock()
        print("[RenderSchedule] renderMsExcluded requestID=\(requestID) reason=\(reason)")
    }

    func cancellationRequested(requestID: UInt64, workID: UInt64, abortedByStage1B: Bool) {
        let t = now()
        lock.lock()
        var metrics = metricsByWorkID[workID] ?? Metrics(workID: workID)
        metrics.cancellationRequestedTime = metrics.cancellationRequestedTime ?? t
        metrics.abortedByStage1B = abortedByStage1B
        metricsByWorkID[workID] = metrics
        lock.unlock()
    }

    func cancelled(requestID: UInt64, workID: UInt64, abortedByStage1B: Bool) {
        let t = now()
        var summary: String?
        lock.lock()
        var metrics = metricsByWorkID[workID] ?? Metrics(workID: workID)
        metrics.abortedByStage1B = metrics.abortedByStage1B || abortedByStage1B
        if metrics.renderAppliedTime == nil {
            metrics.renderRequestedTime = nil
        }
        if !metrics.cancelledSummaryLogged {
            metrics.cancelledSummaryLogged = true
            metricsByWorkID[workID] = metrics
            let start = metrics.startTime ?? metrics.generationRequestedTime ?? metrics.debounceFiredTime ?? metrics.inputEventTime ?? t
            let lifetime = (t - start) * 1000.0
            summary = "[LatencySummary] requestID=\(requestID) workID=\(workID) cancelled=true lifetimeMs=\(String(format: "%.1f", lifetime)) abortedByStage1B=\(metrics.abortedByStage1B)"
        } else {
            metricsByWorkID[workID] = metrics
        }
        lock.unlock()
        if let summary { print(summary) }
    }

    private func successSummary(for metrics: Metrics) -> String {
        let requestID = metrics.requestID ?? 0
        let delayMs = metrics.debounceDelayMs.map { String($0) } ?? "nil"
        
        let tokenizationMs = ms(metrics.tokenizationStartTime, metrics.tokenizationEndTime)
        let generationMs = ms(metrics.llamaStartTime, metrics.generationEndTime)
        
        return """
        [DetailedLatency] requestID=\(requestID) workID=\(metrics.workID)
        Input / debounce:
        - lastKeyEventAt: \(metrics.inputEventTime ?? 0)
        - debounceScheduledAt: \(metrics.debounceScheduledTime ?? 0)
        - debounceDelayMs: \(delayMs)
        - debounceFiredAt: \(metrics.debounceFiredTime ?? 0)
        - debounceActualDelayMs: \(ms(metrics.debounceScheduledTime, metrics.debounceFiredTime))
        
        Request lifecycle:
        - requestCreatedAt: \(metrics.generationRequestedTime ?? 0)
        - requestQueuedAt: \(metrics.generationRequestedTime ?? 0)
        - requestDequeuedAt: \(metrics.startTime ?? 0)
        - staleCancelledBeforeStart: false
        
        Prompt:
        - promptBuildStart: \(metrics.promptStartTime ?? 0)
        - promptBuildEnd: \(metrics.promptEndTime ?? 0)
        - promptBuildMs: \(ms(metrics.promptStartTime, metrics.promptEndTime))
        - boundedPrefixLen: \(metrics.boundedPrefixLen ?? -1)
        - boundedPrefixLineCount: \(metrics.boundedPrefixLineCount ?? -1)
        - suffixLen: \(metrics.suffixLen ?? -1)
        - prefixWasTruncated: \(metrics.prefixWasTruncated ?? false)
        - trailingSpacePreserved: \(metrics.trailingSpacePreserved ?? false)
        
        Tokenization / model:
        - tokenizationStart: \(metrics.tokenizationStartTime ?? 0)
        - tokenizationEnd: \(metrics.tokenizationEndTime ?? 0)
        - tokenizationMs: \(tokenizationMs)
        - promptTokenCount: \(metrics.promptTokenCount ?? -1)
        - generationStart: \(metrics.llamaStartTime ?? 0)
        - firstTokenAt: \(metrics.firstTokenTime ?? 0)
        - firstTokenMs: \(ms(metrics.llamaStartTime, metrics.firstTokenTime))
        - firstUsableAt: \(metrics.firstUsableTime ?? 0)
        - firstUsableTokenMs: \(ms(metrics.llamaStartTime, metrics.firstUsableTime))
        - generatedTokenCount: \(metrics.generatedTokenCount ?? -1)
        - generationEnd: \(metrics.generationEndTime ?? 0)
        - generationMs: \(generationMs)
        
        Render:
        - candidateSelectedAt: \(metrics.renderRequestedTime ?? 0)
        - overlayRenderStart: \(metrics.renderRequestedTime ?? 0)
        - overlayRenderEnd: \(metrics.renderAppliedTime ?? 0)
        - renderMs: \(ms(metrics.renderRequestedTime, metrics.renderAppliedTime))
        - totalPauseToVisibleMs: \(ms(metrics.inputEventTime, metrics.renderAppliedTime))
        
        Classification:
        - promptMode=\(metrics.promptMode ?? "unknown")
        - modelProfile=\(metrics.modelProfile ?? "unknown")
        - completionKind=\(metrics.completionKind ?? "unknown")
        - activeLine='\(metrics.activeLine ?? "")'
        - finalSuggestion='\(metrics.finalSuggestion ?? "")'
        - visibleApplied=\(metrics.visibleApplied)
        - rejectReason=\(metrics.rejectReason ?? "none")
        """
    }
}

class CompletionManager: @unchecked Sendable {
    static let shared = CompletionManager()
    
    var pendingCandidate: String?
    var pendingCandidatePrefix: String = ""
    var displayedCompletion: String?
    var displayedCompletionPrefix: String = ""
    weak var accessibilityMonitor: AccessibilityMonitor?
    weak var overlayWindowController: OverlayWindowController?
    
    /// Thread-safe overlay visibility indicator.
    /// Must NOT access NSWindow.isVisible from background threads (Main Thread Checker violation).
    /// Relies on `displayedCompletion` which is only mutated on the main thread.
    var isOverlayVisible: Bool {
        return displayedCompletion != nil && !displayedCompletion!.isEmpty
    }
    
    private let workController = SuggestionWorkController()
    
    /// Tracks the timestamp of the most recent keystroke for adaptive debounce.
    private var lastKeystrokeTime: Date = .distantPast
    
    var activeSpellCorrection: (misspelled: String, corrected: String)?
    private var activeSnippetKey: String?
    var activeRewriteText: String?
    var activeRewritePID: pid_t?
    var activeRewriteApp: NSRunningApplication?
    var activeSmartReplyPID: pid_t?
    private var rewriteTask: Task<Void, Never>?
    
    private var requestCount: Int = 0
    private var initialRSS: Double = 0.0
    private var warmRSS: Double = 0.0
    private var maxRSS: Double = 0.0

    private func getRSSMemory() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<integer_t>.size)
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        if kerr == KERN_SUCCESS {
            return Double(info.resident_size) / 1024.0 / 1024.0
        } else {
            return 0.0
        }
    }
    
    var isSuppressedUntilNextTyping = false
    private var lastBufferSnapshot: String = ""
    private var generationStartCaretText: String = ""
    private let debounceAuditLock = NSLock()
    private var pendingDebounceText: String?
    private var pendingDebounceTextHash: String?
    private var debounceTextHashByWorkID: [UInt64: String] = [:]
    private var debounceTextByWorkID: [UInt64: String] = [:]
    private var activeGenerationDebounceText: String?
    private var duplicateDebounceSkipCount: UInt64 = 0
    private let axHotPathLock = NSLock()
    private var axHotPathGetTextGenerationCount: UInt64 = 0
    private var axHotPathGetTextStreamCount: UInt64 = 0
    private var axHotPathGetTextRenderCount: UInt64 = 0
    private let resultOwnershipLock = NSLock()
    private var latestResultRequestID: UInt64 = 0
    private var staleCompletedGenerationDiscardCount: UInt64 = 0
    private var staleVisibleUpdateAttemptCount: UInt64 = 0
    private let generationCancellationLock = NSLock()
    private var activeGenerationCancellationToken: LlamaGenerationCancellationToken?
    private let atomicGhostLock = NSLock()
    private var atomicGhostVisibleApplyCountByRequestID: [UInt64: Int] = [:]

    private struct ResultOwnershipSnapshot {
        let latestResultRequestID: UInt64
        let generationResultRequestID: UInt64
        let workID: UInt64
        let currentWorkID: UInt64
        let staleCompletedGenerationDiscardCount: UInt64
        let staleVisibleUpdateAttemptCount: UInt64
    }

    private struct PredictionSnapshot {
        let rawTextBeforeCaret: String
        let source: TextBeforeCaretSource
        let liveBuffer: String
    }

    private struct CanonicalPredictionContext {
        let canonicalTextBeforeCaret: String
        let liveBufferForPrompt: String
        let didAppendLiveBuffer: Bool
        let appendReason: String

        var activeLine: String {
            canonicalTextBeforeCaret.components(separatedBy: .newlines).last ?? ""
        }
    }

    private final class GenerationRequestSnapshot: @unchecked Sendable {
        let requestID: UInt64
        let workID: UInt64
        let canonicalTextBeforeCaret: String
        let source: TextBeforeCaretSource
        let textHash: String

        private let lock = NSLock()
        private var cachedCaretRect: CGRect?
        private var attemptedCaretCapture = false
        private var didLogStreamNoAX = false
        private var didLogSkippedStreamAX = false
        private var didLogFinalNoAX = false
        private var didLogQualityAudit = false

        init(
            requestID: UInt64,
            workID: UInt64,
            canonicalTextBeforeCaret: String,
            source: TextBeforeCaretSource,
            textHash: String
        ) {
            self.requestID = requestID
            self.workID = workID
            self.canonicalTextBeforeCaret = canonicalTextBeforeCaret
            self.source = source
            self.textHash = textHash
        }

        func resolveCaretRect(using monitor: AccessibilityMonitor?) -> (rect: CGRect?, cached: Bool) {
            lock.lock()
            if let cachedCaretRect {
                lock.unlock()
                return (cachedCaretRect, true)
            }
            if attemptedCaretCapture {
                lock.unlock()
                return (nil, false)
            }
            attemptedCaretCapture = true
            lock.unlock()

            let rect = monitor?.getCurrentCaretRect(requestID: requestID)

            lock.lock()
            cachedCaretRect = rect
            lock.unlock()
            return (rect, false)
        }

        func shouldLogStreamNoAX() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            guard !didLogStreamNoAX else { return false }
            didLogStreamNoAX = true
            return true
        }

        func shouldLogSkippedStreamAX() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            guard !didLogSkippedStreamAX else { return false }
            didLogSkippedStreamAX = true
            return true
        }

        func shouldLogFinalNoAX() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            guard !didLogFinalNoAX else { return false }
            didLogFinalNoAX = true
            return true
        }

        func shouldLogQualityAudit(force: Bool = false) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            if force { return true }
            guard !didLogQualityAudit else { return false }
            didLogQualityAudit = true
            return true
        }
    }

    private final class AtomicGhostStreamBuffer: @unchecked Sendable {
        struct Candidate {
            let rawOutput: String
            var suggestion: String
            let mode: String
            let reason: String
            let createdAt: CFAbsoluteTime

            var rawLen: Int { rawOutput.count }
            var finalLen: Int { suggestion.count }
        }

        private let lock = NSLock()
        private var accumulatedRawOutput = ""
        private var lastLoggedBucket = -1
        private var visibleReserved = false
        private var stabilityWindowScheduled = false
        private var latestStableCandidate: Candidate?
        private var repeatedLoopBlocked = false
        private var didLogSuppressedAfterVisible = false
        private var didLogCancelledAfterVisible = false
        private var currentlyDisplayedSuggestion: String = ""

        func observe(partialRawOutput: String, requestID: UInt64) -> String {
            let accumulatedChars: Int
            let shouldLog: Bool
            let accumulated: String

            lock.lock()
            if accumulatedRawOutput.isEmpty || partialRawOutput.hasPrefix(accumulatedRawOutput) {
                accumulatedRawOutput = partialRawOutput
            } else if accumulatedRawOutput.hasPrefix(partialRawOutput) {
                // Older cumulative callback; keep the newer longer text.
            } else {
                accumulatedRawOutput += partialRawOutput
            }

            accumulatedChars = accumulatedRawOutput.count
            accumulated = accumulatedRawOutput
            let bucket = accumulatedChars == 0 ? 0 : accumulatedChars / 32
            shouldLog = bucket != lastLoggedBucket
            if shouldLog {
                lastLoggedBucket = bucket
            }
            lock.unlock()

            if shouldLog {
                print("[AtomicGhost] suppressedStreamRender requestID=\(requestID) accumulatedChars=\(accumulatedChars)")
            }
            return accumulated
        }

        func finalRawOutput(engineOutput: String) -> String {
            lock.lock()
            let accumulated = accumulatedRawOutput
            lock.unlock()

            return engineOutput.isEmpty ? accumulated : engineOutput
        }

        func isVisibleReserved() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            return visibleReserved
        }

        func isFullyUpgraded() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            let currentWords = currentlyDisplayedSuggestion.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
            return visibleReserved && currentWords.count >= 6
        }

        func tryUpdateDisplayedSuggestion(_ newSuggestion: String) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            
            let newWords = newSuggestion.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
            
            // Limit suggestions to generally 2-6 words
            guard newWords.count <= 6 else { return false }
            
            if !visibleReserved {
                guard newWords.count >= 1 else { return false }
                visibleReserved = true
                currentlyDisplayedSuggestion = newSuggestion
                return true
            }
            
            // This is a subsequent candidate. Check if it's a valid upgrade.
            let currentWords = currentlyDisplayedSuggestion.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
            
            guard newWords.count > currentWords.count else { return false }
            
            let cleanNew = newSuggestion.lowercased().replacingOccurrences(of: " ", with: "")
            let cleanCurrent = currentlyDisplayedSuggestion.lowercased().replacingOccurrences(of: " ", with: "")
            if cleanNew.hasPrefix(cleanCurrent) {
                currentlyDisplayedSuggestion = newSuggestion
                return true
            }
            
            return false
        }

        func reserveVisibleApply() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            guard !visibleReserved else { return false }
            visibleReserved = true
            return true
        }

        func recordStableCandidate(_ candidate: Candidate) {
            lock.lock()
            latestStableCandidate = candidate
            lock.unlock()
        }

        func latestCandidateForStabilityWindow() -> Candidate? {
            lock.lock()
            defer { lock.unlock() }
            guard !repeatedLoopBlocked else { return nil }
            return latestStableCandidate
        }

        func shouldScheduleStabilityWindow() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            guard !stabilityWindowScheduled else { return false }
            stabilityWindowScheduled = true
            return true
        }

        func markRepeatedLoopBlockedBeforeVisible(requestID: UInt64) {
            lock.lock()
            let shouldLog = !repeatedLoopBlocked && !visibleReserved
            repeatedLoopBlocked = true
            latestStableCandidate = nil
            lock.unlock()

            if shouldLog {
                print("[AtomicGhost] repeatedLoopBlockedBeforeVisible requestID=\(requestID)")
            }
        }

        func logSuppressedAfterVisible(requestID: UInt64) {
            lock.lock()
            let shouldLog = visibleReserved && !didLogSuppressedAfterVisible
            if shouldLog {
                didLogSuppressedAfterVisible = true
            }
            lock.unlock()

            if shouldLog {
                print("[AtomicGhost] suppressedAfterVisible requestID=\(requestID)")
            }
        }

        func logCancelledAfterVisible(requestID: UInt64) {
            lock.lock()
            let shouldLog = !didLogCancelledAfterVisible
            if shouldLog {
                didLogCancelledAfterVisible = true
            }
            lock.unlock()

            if shouldLog {
                print("[AtomicGhost] cancelledAfterVisible requestID=\(requestID)")
            }
        }
    }

    private func contextAuditPreview(_ text: String, limit: Int = 220) -> String {
        let escaped = text
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\t", with: "\\t")
        if escaped.count <= limit { return escaped }
        return "..." + String(escaped.suffix(limit))
    }

    private func logContextAudit(_ message: String) {
        print("[TypeFlow-ContextAudit] \(message)")
    }

    private func qualityAuditPreview(_ text: String, limit: Int = 220) -> String {
        let escaped = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\t", with: "\\t")
            .replacingOccurrences(of: "'", with: "\\'")
        if escaped.count <= limit { return escaped }
        return "..." + String(escaped.suffix(limit))
    }

    private func qualityAuditReason(
        rawOutput: String,
        processedOutput: String,
        finalSuggestion: String,
        activeLine: String
    ) -> String {
        let trimmedSuggestion = finalSuggestion.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedRaw = rawOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowerRaw = trimmedRaw.lowercased()
        let assistantLikePrefixes = [
            "i'm not sure",
            "i am not sure",
            "i'm sorry",
            "i cannot",
            "i can't",
            "as an ai",
            "sure,",
            "here's",
            "here is",
            "let me",
            "it sounds like"
        ]

        if finalSuggestion.isEmpty {
            return "empty"
        }
        if assistantLikePrefixes.contains(where: { lowerRaw.hasPrefix($0) || trimmedSuggestion.lowercased().hasPrefix($0) }) {
            return "assistantLike"
        }

        let punctuationAndWhitespace = CharacterSet.punctuationCharacters
            .union(.symbols)
            .union(.whitespacesAndNewlines)
        if !trimmedSuggestion.isEmpty,
           trimmedSuggestion.unicodeScalars.allSatisfy({ punctuationAndWhitespace.contains($0) }) {
            return "punctuationOnly"
        }

        if finalSuggestion != finalSuggestion.trimmingCharacters(in: .whitespacesAndNewlines) {
            return "trailingWhitespace"
        }

        let currentWord = activeLine
            .components(separatedBy: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
            .last ?? ""
        if !currentWord.isEmpty && finalSuggestion.hasPrefix(currentWord) {
            return "duplicatePrefix"
        }
        if !activeLine.isEmpty && finalSuggestion.hasPrefix(activeLine) {
            return "duplicatePrefix"
        }

        if finalSuggestion.count > 160 {
            return "tooLong"
        }

        _ = processedOutput
        return "validContinuation"
    }

    private func logQualityAudit(
        requestSnapshot: GenerationRequestSnapshot,
        rawOutput: String,
        processedOutput: String,
        finalSuggestion: String,
        phase: String,
        force: Bool = false
    ) {
        guard requestSnapshot.shouldLogQualityAudit(force: force) else { return }

        let activeLine = requestSnapshot.canonicalTextBeforeCaret
            .components(separatedBy: .newlines)
            .last ?? ""
        let reason = qualityAuditReason(
            rawOutput: rawOutput,
            processedOutput: processedOutput,
            finalSuggestion: finalSuggestion,
            activeLine: activeLine
        )
        let accepted = reason == "validContinuation"
        let rejectionReason = accepted ? "none" : reason

        print("[QualityAudit] requestID=\(requestSnapshot.requestID) phase=\(phase) textBeforeCaret='\(qualityAuditPreview(requestSnapshot.canonicalTextBeforeCaret))' rawOutput='\(qualityAuditPreview(rawOutput))' processedOutput='\(qualityAuditPreview(processedOutput))' accepted=\(accepted) rejectionReason=\(rejectionReason)")
        print("[QualityAudit] reason=\(reason) source=\(requestSnapshot.source.rawValue) activeLine='\(qualityAuditPreview(activeLine))' finalSuggestion='\(qualityAuditPreview(finalSuggestion))'")
    }

    private func canonicalizePredictionSnapshot(_ snapshot: PredictionSnapshot) -> CanonicalPredictionContext {
        let rawText = snapshot.rawTextBeforeCaret
        let liveBuffer = snapshot.liveBuffer

        var canonicalText = rawText
        var didAppend = false
        var reason = ""

        switch snapshot.source {
        case .keystrokeBufferFallback:
            reason = "source is keystrokeBufferFallback; fallback is already complete best-known cursor text"
        case .providedText:
            reason = "source is providedText; explicit caller text is already canonical"
        case .none:
            if rawText.isEmpty && !liveBuffer.isEmpty {
                canonicalText = liveBuffer
                reason = "no AX text; using liveBuffer as canonical fallback"
            } else {
                reason = "no source text available"
            }
        case .axValue, .axSelectedText, .axStringForRange:
            if liveBuffer.isEmpty {
                reason = "AX text available; no liveBuffer to reconcile"
            } else if rawText.hasSuffix(liveBuffer) {
                reason = "AX text already contains liveBuffer suffix"
            } else if rawText.isEmpty {
                canonicalText = liveBuffer
                didAppend = true
                reason = "AX text empty; liveBuffer becomes canonical cursor text"
            } else if liveBuffer.hasPrefix(rawText) {
                canonicalText = liveBuffer
                didAppend = true
                reason = "liveBuffer extends the complete AX text"
            } else {
                let lines = rawText.components(separatedBy: .newlines)
                let activeLine = lines.last ?? ""
                if !activeLine.isEmpty && liveBuffer.hasPrefix(activeLine) {
                    let previousLines = lines.dropLast().joined(separator: "\n")
                    canonicalText = previousLines.isEmpty ? liveBuffer : previousLines + "\n" + liveBuffer
                    didAppend = true
                    reason = "liveBuffer extends AX active line"
                } else {
                    reason = "AX text and liveBuffer do not have a provable suffix relationship; no append"
                }
            }
        }

        let context = CanonicalPredictionContext(
            canonicalTextBeforeCaret: canonicalText,
            liveBufferForPrompt: "",
            didAppendLiveBuffer: didAppend,
            appendReason: reason
        )

        print("""
        [Context Canonicalization Audit]
        AX source/method: \(snapshot.source.rawValue)
        raw textBeforeCaret: '\(contextAuditPreview(rawText))'
        raw liveBuffer: '\(contextAuditPreview(liveBuffer))'
        didAppendLiveBuffer: \(didAppend)
        append reason: \(reason)
        canonicalTextBeforeCaret: '\(contextAuditPreview(canonicalText))'
        activeLine sent to prompt: '\(contextAuditPreview(context.activeLine))'
        """)

        return context
    }

    private func syncFallbackBufferIfAuthoritative(_ context: CanonicalPredictionContext, source: TextBeforeCaretSource) {
        accessibilityMonitor?.synchronizeKeystrokeBuffer(
            withCanonicalText: context.canonicalTextBeforeCaret,
            source: source
        )
    }
    
    var isRewrite: Bool {
        return activeRewritePID != nil || activeRewriteText != nil
    }
    
    var isSmartReply: Bool {
        return activeSmartReplyPID != nil
    }

    private func beginResultRequest(activeLine: String) -> UInt64 {
        resultOwnershipLock.lock()
        latestResultRequestID &+= 1
        let requestID = latestResultRequestID
        resultOwnershipLock.unlock()

        print("[TypeFlow-Debug] Stage1A: result request #\(requestID) started for '\(activeLine.suffix(40))'")
        logStage1ACounters(context: "begin-request", generationResultRequestID: requestID, workID: workController.currentWorkID)
        return requestID
    }

    private func invalidateGenerationResults(reason: String, bufferSnapshot: String) {
        resultOwnershipLock.lock()
        latestResultRequestID &+= 1
        let requestID = latestResultRequestID
        resultOwnershipLock.unlock()

        print("[TypeFlow-Debug] Stage1A: result ownership advanced to #\(requestID) (\(reason)) for '\(bufferSnapshot.suffix(40))'")
        logStage1ACounters(context: "ownership-advanced-\(reason)", generationResultRequestID: requestID, workID: workController.currentWorkID)
    }

    private func isLatestResultRequest(_ requestID: UInt64) -> Bool {
        resultOwnershipLock.lock()
        defer { resultOwnershipLock.unlock() }
        return requestID == latestResultRequestID
    }

    func isRenderRequestCurrent(_ requestID: UInt64) -> Bool {
        return isLatestResultRequest(requestID)
    }

    private func isGenerationResultCurrent(requestID: UInt64, workID: UInt64) -> Bool {
        return workController.isCurrent(workID) && isLatestResultRequest(requestID)
    }

    private func shouldRenderGenerationResult(requestID: UInt64, workID: UInt64, source: String) -> Bool {
        guard isGenerationResultCurrent(requestID: requestID, workID: workID) else {
            logRenderDecision(allowed: false, requestID: requestID, workID: workID, source: source)
            recordStaleVisibleUpdateAttempt(requestID: requestID, workID: workID, source: source)
            return false
        }
        logRenderDecision(allowed: true, requestID: requestID, workID: workID, source: source)
        return true
    }

    private func shouldRenderOwnedResult(requestID: UInt64, workID: UInt64, source: String) -> Bool {
        guard isLatestResultRequest(requestID) else {
            logRenderDecision(allowed: false, requestID: requestID, workID: workID, source: source)
            recordStaleVisibleUpdateAttempt(requestID: requestID, workID: workID, source: source)
            return false
        }
        logRenderDecision(allowed: true, requestID: requestID, workID: workID, source: source)
        return true
    }

    private func makeResultOwnershipSnapshot(requestID: UInt64, workID: UInt64) -> ResultOwnershipSnapshot {
        let currentWorkID = workController.currentWorkID
        resultOwnershipLock.lock()
        let snapshot = ResultOwnershipSnapshot(
            latestResultRequestID: latestResultRequestID,
            generationResultRequestID: requestID,
            workID: workID,
            currentWorkID: currentWorkID,
            staleCompletedGenerationDiscardCount: staleCompletedGenerationDiscardCount,
            staleVisibleUpdateAttemptCount: staleVisibleUpdateAttemptCount
        )
        resultOwnershipLock.unlock()
        return snapshot
    }

    private func logRenderDecision(allowed: Bool, requestID: UInt64, workID: UInt64, source: String) {
        let snapshot = makeResultOwnershipSnapshot(requestID: requestID, workID: workID)
        print("[TypeFlow-Debug] Stage1A: render attempt \(allowed ? "ALLOWED" : "BLOCKED") from \(source) — latestResultRequestID=\(snapshot.latestResultRequestID), generationResultRequestID=\(snapshot.generationResultRequestID), workID=\(snapshot.workID), currentWorkID=\(snapshot.currentWorkID), staleCompletedDiscards=\(snapshot.staleCompletedGenerationDiscardCount), staleVisibleBlocks=\(snapshot.staleVisibleUpdateAttemptCount)")
    }

    private func logStage1ACounters(context: String, generationResultRequestID: UInt64, workID: UInt64) {
        let snapshot = makeResultOwnershipSnapshot(requestID: generationResultRequestID, workID: workID)
        print("[TypeFlow-Debug] Stage1A: counters after \(context) — latestResultRequestID=\(snapshot.latestResultRequestID), generationResultRequestID=\(snapshot.generationResultRequestID), workID=\(snapshot.workID), currentWorkID=\(snapshot.currentWorkID), staleCompletedDiscards=\(snapshot.staleCompletedGenerationDiscardCount), staleVisibleBlocks=\(snapshot.staleVisibleUpdateAttemptCount)")
    }

    private func recordStaleCompletedGenerationDiscard(requestID: UInt64, workID: UInt64) {
        resultOwnershipLock.lock()
        staleCompletedGenerationDiscardCount &+= 1
        let discardCount = staleCompletedGenerationDiscardCount
        let latestID = latestResultRequestID
        resultOwnershipLock.unlock()

        print("[TypeFlow-Debug] Stage1A: discarded completed stale generation request #\(requestID) (latest #\(latestID), workID \(workID)). Total stale completed discards: \(discardCount)")
        logStage1ACounters(context: "stale-completed-discard", generationResultRequestID: requestID, workID: workID)
    }

    private func recordStaleVisibleUpdateAttempt(requestID: UInt64, workID: UInt64, source: String) {
        resultOwnershipLock.lock()
        staleVisibleUpdateAttemptCount &+= 1
        let attemptCount = staleVisibleUpdateAttemptCount
        let latestID = latestResultRequestID
        resultOwnershipLock.unlock()

        print("[TypeFlow-Debug] Stage1A: blocked stale visible update from \(source) for request #\(requestID) (latest #\(latestID), workID \(workID)). Total blocked visible attempts: \(attemptCount)")
        logStage1ACounters(context: "stale-visible-block-\(source)", generationResultRequestID: requestID, workID: workID)
    }

    private func installGenerationCancellationToken(_ token: LlamaGenerationCancellationToken) {
        generationCancellationLock.lock()
        let previousToken = activeGenerationCancellationToken
        activeGenerationCancellationToken = token
        generationCancellationLock.unlock()

        if let previousToken, previousToken !== token, previousToken.requestCancellation(reason: "new-generation") {
            LatencyInstrumentation.shared.cancellationRequested(requestID: previousToken.requestID, workID: previousToken.workID, abortedByStage1B: true)
            print("[Stage1B] cancellation requested oldRequestID=\(previousToken.requestID) reason=new-generation")
        }
        print("[Stage1B] new generation started with fresh cancellation token requestID=\(token.requestID)")
    }

    private func clearGenerationCancellationTokenIfCurrent(_ token: LlamaGenerationCancellationToken) {
        generationCancellationLock.lock()
        if activeGenerationCancellationToken === token {
            activeGenerationCancellationToken = nil
        }
        generationCancellationLock.unlock()
    }

    private func requestActiveGenerationAbort(reason: String) {
        generationCancellationLock.lock()
        let token = activeGenerationCancellationToken
        generationCancellationLock.unlock()

        guard let token else { return }
        if token.requestCancellation(reason: reason) {
            LatencyInstrumentation.shared.cancellationRequested(requestID: token.requestID, workID: token.workID, abortedByStage1B: true)
            print("[Stage1B] cancellation requested oldRequestID=\(token.requestID) reason=\(reason)")
        }
    }
    
    private init() {}

    private func debounceAuditHash(_ text: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(format: "%016llx", hash)
    }

    private func debounceAuditTextChanged(_ text: String) -> (textHash: String, shouldSkip: Bool) {
        let textHash = debounceAuditHash(text)
        let timestamp = String(format: "%.6f", CFAbsoluteTimeGetCurrent())
        print("[DebounceAudit] textChanged received textHash=\(textHash) timestamp=\(timestamp)")

        debounceAuditLock.lock()
        let isPendingDuplicate = pendingDebounceText == text
        let isActiveGenerationText = activeGenerationDebounceText == text
        debounceAuditLock.unlock()
        let isRunningDuplicate = isActiveGenerationText && workController.isGenerationRunning
        if isPendingDuplicate || isRunningDuplicate {
            debounceAuditLock.lock()
            duplicateDebounceSkipCount &+= 1
            let count = duplicateDebounceSkipCount
            debounceAuditLock.unlock()
            print("[DebounceAudit] skipped duplicate textHash=\(textHash) count=\(count)")
            return (textHash, true)
        }
        return (textHash, false)
    }

    private func debounceAuditPendingBeforeSchedule() -> Bool {
        debounceAuditLock.lock()
        defer { debounceAuditLock.unlock() }
        return pendingDebounceText != nil
    }

    private func debounceAuditScheduled(text: String, textHash: String, workID: UInt64, delayMs: Int) {
        debounceAuditLock.lock()
        pendingDebounceText = text
        pendingDebounceTextHash = textHash
        debounceTextByWorkID[workID] = text
        debounceTextHashByWorkID[workID] = textHash
        debounceAuditLock.unlock()
        print("[DebounceAudit] scheduled owner=CompletionManager delayMs=\(delayMs) textHash=\(textHash) workID=\(workID)")
    }

    private func debounceAuditMarkFired(workID: UInt64) -> String? {
        debounceAuditLock.lock()
        let text = debounceTextByWorkID[workID]
        let textHash = debounceTextHashByWorkID[workID] ?? pendingDebounceTextHash
        if let text {
            activeGenerationDebounceText = text
        }
        if pendingDebounceText == text {
            pendingDebounceText = nil
            pendingDebounceTextHash = nil
        }
        debounceAuditLock.unlock()
        return textHash
    }

    private func debounceAuditFired(requestID: UInt64, workID: UInt64) {
        debounceAuditLock.lock()
        let textHash = debounceTextHashByWorkID[workID] ?? debounceAuditHash(generationStartCaretText)
        debounceAuditLock.unlock()
        print("[DebounceAudit] fired requestID=\(requestID) textHash=\(textHash) workID=\(workID)")
    }

    private func debounceAuditGenerationFinished(workID: UInt64) {
        debounceAuditLock.lock()
        if let text = debounceTextByWorkID[workID], activeGenerationDebounceText == text {
            activeGenerationDebounceText = nil
        }
        debounceTextByWorkID.removeValue(forKey: workID)
        debounceTextHashByWorkID.removeValue(forKey: workID)
        debounceAuditLock.unlock()
    }

    private func debounceAuditReset(reason: String) {
        debounceAuditLock.lock()
        pendingDebounceText = nil
        pendingDebounceTextHash = nil
        debounceTextByWorkID.removeAll()
        debounceTextHashByWorkID.removeAll()
        activeGenerationDebounceText = nil
        debounceAuditLock.unlock()
        print("[DebounceAudit] reset reason=\(reason)")
    }

    private func recordAXHotPathGetTextRead(phase: String) {
        axHotPathLock.lock()
        switch phase {
        case "generation":
            axHotPathGetTextGenerationCount &+= 1
        case "stream":
            axHotPathGetTextStreamCount &+= 1
        case "render":
            axHotPathGetTextRenderCount &+= 1
        default:
            break
        }
        let generation = axHotPathGetTextGenerationCount
        let stream = axHotPathGetTextStreamCount
        let render = axHotPathGetTextRenderCount
        axHotPathLock.unlock()
        print("[AXHotPath] getTextBeforeCaret count generation=\(generation) stream=\(stream) render=\(render)")
    }

    func recordAtomicGhostVisibleApply(requestID: UInt64, textLen: Int) {
        atomicGhostLock.lock()
        let count = (atomicGhostVisibleApplyCountByRequestID[requestID] ?? 0) + 1
        atomicGhostVisibleApplyCountByRequestID[requestID] = count
        atomicGhostLock.unlock()

        print("[AtomicGhost] visibleApply requestID=\(requestID) countForRequest=\(count) textLen=\(textLen)")
        if count > 1 {
            print("[AtomicGhost] progressiveRenderViolation requestID=\(requestID) countForRequest=\(count)")
        }
    }

    private func resetAtomicGhostVisibleApplyCount(requestID: UInt64) {
        atomicGhostLock.lock()
        atomicGhostVisibleApplyCountByRequestID[requestID] = 0
        atomicGhostLock.unlock()
        print("[AtomicGhost] mode=earlyAtomic requestID=\(requestID)")
    }

    private func atomicGhostMode(for contract: SuggestionInteractionState.ContinuationContract) -> String {
        return contract.mode == "partialWord" ? "midWord" : "afterSpace"
    }

    private func atomicGhostContainsCompleteWordBoundary(_ suggestion: String) -> Bool {
        var hasWordCharacter = false
        for character in suggestion {
            if character.isLetter || character.isNumber {
                hasWordCharacter = true
            } else if hasWordCharacter && (character.isWhitespace || character.isPunctuation) {
                return true
            }
        }
        return false
    }

    private func atomicGhostCandidate(
        rawOutput: String,
        activeLine: String,
        requestID: UInt64,
        streamBuffer: AtomicGhostStreamBuffer,
        phase: String
    ) -> (candidate: AtomicGhostStreamBuffer.Candidate?, contract: SuggestionInteractionState.ContinuationContract) {
        let contract = SuggestionInteractionState.canonicalizeContinuation(
            activeLine: activeLine,
            rawCompletion: stripMarkdown(rawOutput)
        )

        guard contract.reason != "repeatedTokenLoop" else {
            streamBuffer.markRepeatedLoopBlockedBeforeVisible(requestID: requestID)
            return (nil, contract)
        }

        guard contract.isRenderable else {
            return (nil, contract)
        }

        var suggestion = contract.suggestion
        if let newlineRange = suggestion.range(of: "\n") {
            suggestion = String(suggestion[..<newlineRange.lowerBound])
        }
        guard !suggestion.isEmpty else {
            return (nil, contract)
        }

        let mode = atomicGhostMode(for: contract)
        let candidate = AtomicGhostStreamBuffer.Candidate(
            rawOutput: rawOutput,
            suggestion: suggestion,
            mode: mode,
            reason: contract.reason,
            createdAt: CFAbsoluteTimeGetCurrent()
        )
        print("[AtomicGhost] \(phase) requestID=\(requestID) rawLen=\(candidate.rawLen) finalLen=\(candidate.finalLen) mode=\(mode) reason=\(candidate.reason)")
        return (candidate, contract)
    }

    private func tryApplyAtomicGhostCandidate(
        _ candidate: AtomicGhostStreamBuffer.Candidate,
        requestSnapshot: GenerationRequestSnapshot,
        streamBuffer: AtomicGhostStreamBuffer,
        cancellationToken: LlamaGenerationCancellationToken,
        source: String,
        recordShown: Bool
    ) {
        let requestID = requestSnapshot.requestID
        let workID = requestSnapshot.workID
        guard !cancellationToken.isCancelled else { return }
        guard shouldRenderGenerationResult(requestID: requestID, workID: workID, source: source) else { return }
        // Extract partial word if any
        let activeLine = requestSnapshot.canonicalTextBeforeCaret
        let wordBoundaryChars: Set<Character> = [
            " ", "\t", ".", "_", "(", ")", ":", "/", ",", ";",
            "{", "}", "=", "+", "-", "*", "&", "|", "!", "?",
            "\"", "'", "[", "]", "<", ">"
        ]
        
        var partialWord = ""
        if !activeLine.isEmpty && !wordBoundaryChars.contains(activeLine.last!) {
            var partialStart = activeLine.endIndex
            var idx = activeLine.index(before: activeLine.endIndex)
            while idx >= activeLine.startIndex {
                if wordBoundaryChars.contains(activeLine[idx]) {
                    partialStart = activeLine.index(after: idx)
                    break
                }
                if idx == activeLine.startIndex {
                    partialStart = activeLine.startIndex
                    break
                }
                idx = activeLine.index(before: idx)
            }
            partialWord = String(activeLine[partialStart...])
        }

        var candidate = candidate
        let salvageMode = UserDefaults.standard.integer(forKey: "SalvageMode")
        if salvageMode > 0 {
            var s = candidate.suggestion
            
            // Mode B (salvageMode >= 1)
            // Strip HTML/XML tags
            s = s.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression, range: nil)
            
            // Decode basic entities (very simple)
            s = s.replacingOccurrences(of: "&lt;", with: "<")
            s = s.replacingOccurrences(of: "&gt;", with: ">")
            s = s.replacingOccurrences(of: "&amp;", with: "&")
            s = s.replacingOccurrences(of: "&quot;", with: "\"")
            
            // Strip markdown emphasis/backticks
            s = s.replacingOccurrences(of: "\\*{1,3}([^\\*]+)\\*{1,3}", with: "$1", options: .regularExpression, range: nil)
            s = s.replacingOccurrences(of: "_{1,3}([^_]+)_{1,3}", with: "$1", options: .regularExpression, range: nil)
            s = s.replacingOccurrences(of: "`([^`]+)`", with: "$1", options: .regularExpression, range: nil)
            
            // Normalize whitespace
            s = s.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            
            // Strip FIM/chat control tokens if leaked
            let profile = ModelProfile.current()
            for stopToken in profile.stopTokens {
                s = s.replacingOccurrences(of: stopToken, with: "")
            }
            if let prefix = profile.fimPrefix { s = s.replacingOccurrences(of: prefix, with: "") }
            if let suffix = profile.fimSuffix { s = s.replacingOccurrences(of: suffix, with: "") }
            if let middle = profile.fimMiddle { s = s.replacingOccurrences(of: middle, with: "") }
            
            // Truncate before Explanation:, Note:, Output:, markdown headings, or \n\n
            if let idx = s.range(of: "Explanation:")?.lowerBound { s = String(s[..<idx]) }
            if let idx = s.range(of: "Note:")?.lowerBound { s = String(s[..<idx]) }
            if let idx = s.range(of: "Output:")?.lowerBound { s = String(s[..<idx]) }
            if let idx = s.range(of: "\n\n")?.lowerBound { s = String(s[..<idx]) }
            if let idx = s.range(of: "\n#")?.lowerBound { s = String(s[..<idx]) }
            
            s = s.trimmingCharacters(in: CharacterSet(charactersIn: " \t\n\r,-:;"))
            
            // Active line prefix stripping
            let lowerS = s.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            let lowerActive = activeLine.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            if !lowerActive.isEmpty && lowerS.hasPrefix(lowerActive) && lowerS.count > lowerActive.count {
                if let range = s.lowercased().range(of: lowerActive) {
                    s = String(s[range.upperBound...])
                    s = s.trimmingCharacters(in: CharacterSet(charactersIn: " \t,-:;"))
                }
            }
            
            // Mode C (salvageMode == 2)
            if salvageMode == 2 {
                // Strip list prefixes
                s = s.replacingOccurrences(of: "^[\\s]*[\\d]+[\\)\\.]\\s+", with: "", options: .regularExpression, range: nil)
                s = s.replacingOccurrences(of: "^[\\s]*[\\-\\*]\\s+", with: "", options: .regularExpression, range: nil)
                
                let codeSyntax = CharacterSet(charactersIn: "{}();<>=")
                let isCode = s.rangeOfCharacter(from: codeSyntax) != nil || s.uppercased().contains("SELECT") || s.uppercased().contains("WHERE")
                
                if !isCode {
                    let sentenceBoundaries = CharacterSet(charactersIn: ".!?")
                    if let boundIdx = s.rangeOfCharacter(from: sentenceBoundaries)?.lowerBound { s = String(s[..<boundIdx]) }
                    
                    let words = s.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
                    if words.count > 8 { s = words.prefix(8).joined(separator: " ") }
                }
            }
            
            candidate.suggestion = s.trimmingCharacters(in: .whitespacesAndNewlines)
            
            if candidate.suggestion != candidate.rawOutput {
                print("[SalvageAudit] requestID=\(requestID) mode=\(salvageMode) Salvaged raw='\(candidate.rawOutput.replacingOccurrences(of: "\n", with: "\\n"))' -> '\(candidate.suggestion)'")
            }
        }
        
        // Visible Usefulness Gate
        var accepted = true
        var rejectionReason = ""
        let suggestion = candidate.suggestion

        // activeLineRestart check
        let cleanedNorm = suggestion.components(separatedBy: CharacterSet.alphanumerics.inverted).joined(separator: " ").lowercased().components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        let activeNorm = activeLine.components(separatedBy: CharacterSet.alphanumerics.inverted).joined(separator: " ").lowercased().components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        
        if cleanedNorm.count >= 3 && activeNorm.count >= 3 {
            if Array(cleanedNorm.prefix(3)) == Array(activeNorm.prefix(3)) {
                accepted = false; rejectionReason = "activeLineRestart"
            } else if cleanedNorm[0] == activeNorm[0] && cleanedNorm[1] == activeNorm[1] {
                accepted = false; rejectionReason = "activeLineRestart"
            }
        }

        // malformedQuote check
        if accepted {
            if suggestion.hasPrefix("I\"") || suggestion == "I'" {
                accepted = false; rejectionReason = "malformedQuote"
            } else if suggestion.hasPrefix("'") || suggestion.hasSuffix("'") {
                accepted = false; rejectionReason = "malformedQuote"
            } else if suggestion.hasPrefix("\"") || suggestion.hasSuffix("\"") {
                accepted = false; rejectionReason = "malformedQuote"
            } else if suggestion.allSatisfy({ !$0.isLetter && !$0.isNumber }) && !suggestion.isEmpty {
                accepted = false; rejectionReason = "malformedQuote" // repurposing for punctuation-only output
            }
        }
        
        // genericFragment check
        if accepted {
            let generics = ["it is a good", "this is a", "there are", "the more", "states that"]
            let lowerSug = suggestion.lowercased()
            if generics.contains(lowerSug) || generics.contains(where: { lowerSug.hasPrefix($0 + " ") }) {
                accepted = false; rejectionReason = "genericFragment"
            }
        }

        if accepted {
            if suggestion.contains("<") && suggestion.contains(">") {
                accepted = false; rejectionReason = "markupOrFormatting"
            } else if suggestion.contains("```") {
                accepted = false; rejectionReason = "markupOrFormatting"
            } else if suggestion.contains("](") && suggestion.contains("[") && suggestion.contains(")") {
                accepted = false; rejectionReason = "markupOrFormatting"
            } else if (suggestion.hasPrefix("**") && suggestion.hasSuffix("**")) || 
                      (suggestion.hasPrefix("*") && suggestion.hasSuffix("*") && suggestion.count > 2) ||
                      (suggestion.hasPrefix("_") && suggestion.hasSuffix("_") && suggestion.count > 2) {
                accepted = false; rejectionReason = "markupOrFormatting"
            }
        }

        if accepted {
            // Local context repetition gate
            let suggestionWords = suggestion.components(separatedBy: CharacterSet.letters.inverted).filter { !$0.isEmpty }
            if suggestionWords.count >= 2 {
                let twoWordPhrase = suggestionWords.prefix(2).joined(separator: " ").lowercased()
                let previousLines = requestSnapshot.canonicalTextBeforeCaret.components(separatedBy: .newlines).dropLast().joined(separator: "\n").lowercased()
                if !previousLines.isEmpty && previousLines.contains(twoWordPhrase) {
                    accepted = false; rejectionReason = "localContextRepeat"
                }
            }
        }

        if accepted {
            if candidate.mode == "midWord" {
                let isPunctuationOnly = suggestion.allSatisfy { !$0.isLetter && !$0.isNumber }
                
                if suggestion.isEmpty {
                    accepted = false; rejectionReason = "empty"
                } else if isPunctuationOnly {
                    accepted = false; rejectionReason = "punctuationOnly"
                } else if suggestion.first!.isWhitespace {
                    accepted = false; rejectionReason = "leadingWhitespace"
                } else if !partialWord.isEmpty && partialWord.first!.isLowercase && suggestion.first!.isUppercase {
                    accepted = false; rejectionReason = "uppercaseMismatched"
                } else if !suggestion.isEmpty && !suggestion.first!.isLetter && !suggestion.first!.isNumber {
                    accepted = false; rejectionReason = "invalidPartialWordSuffix"
                } else {
                    let firstSuffixSegment = suggestion.components(separatedBy: CharacterSet.letters.inverted).first ?? ""
                    let completedWord = partialWord + firstSuffixSegment
                    let lowerCompletedWord = completedWord.lowercased()
                    
                    if partialWord.count < 2 {
                        // 1-char stems: reject
                        accepted = false; rejectionReason = "shortStemSpeculativeMidWord"
                    } else {
                        let spellRange = NSSpellChecker.shared.checkSpelling(of: completedWord, startingAt: 0)
                        let isWordSpelledCorrectly = (spellRange.location == NSNotFound)
                        
                        if !isWordSpelledCorrectly {
                            accepted = false; rejectionReason = "invalidPartialWordSuffix"
                        } else if suggestion.lowercased().hasPrefix(partialWord.lowercased()) {
                            // Suffix must not restart/duplicate the typed word
                            accepted = false; rejectionReason = "invalidPartialWordSuffix"
                        } else if partialWord.count == 2 {
                            // 2-char stems: allow only if the completed word is a common/strong word, or is long enough (>= 5 chars)
                            let isCommonWord = ["the", "this", "that", "there", "their", "then", "them", "these", "they", "to", "you", "your", "with", "would", "about", "could", "should", "will", "from"].contains(lowerCompletedWord)
                            let isLongValidWord = completedWord.count >= 5
                            if !isCommonWord && !isLongValidWord {
                                accepted = false; rejectionReason = "shortStemSpeculativeMidWord"
                            }
                        } else {
                            // 3+ char stems: allowed if the completed word is spelled correctly. No whitelist or boundary required!
                        }
                    }
                }
            } else if candidate.mode == "afterSpace" {
                let words = suggestion.components(separatedBy: CharacterSet.letters.inverted).filter { !$0.isEmpty }
                let isPunctuationOnly = suggestion.allSatisfy { !$0.isLetter && !$0.isNumber }
                let lowerSug = suggestion.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                
                let chattyFillers = ["mhm.", "mhm", "uh", "um", "yeah", "okay", "ok", "yes", "i mean", "like,", "so,"]
                
                let isShortCommonWord = ["the", "a", "an", "this", "that", "it", "we", "in", "of", "to", "for", "on", "as", "is", "are", "was", "were", "and", "or", "but"].contains(lowerSug)
                let activeWords = activeLine.lowercased().components(separatedBy: CharacterSet.letters.inverted).filter { !$0.isEmpty }
                
                let isLocalContextRepeat = (!isShortCommonWord && words.count == 1 && activeWords.contains(words[0])) ||
                                           (words.count > 1 && activeLine.lowercased().contains(lowerSug))
                
                let isRepeatedTokenLoop = words.count == 2 && words[0] == words[1]
                
                if isPunctuationOnly {
                    accepted = false; rejectionReason = "punctuationOnly"
                } else if chattyFillers.contains(lowerSug) {
                    accepted = false; rejectionReason = "fillerOrChatty"
                } else if isRepeatedTokenLoop {
                    accepted = false; rejectionReason = "repeatedTokenLoop"
                } else if isLocalContextRepeat {
                    accepted = false; rejectionReason = "localContextRepeat"
                } else if suggestion.count <= 2 {
                    accepted = false; rejectionReason = "tooShortAfterSpace"
                } else if words.count >= 2 && words.allSatisfy({ $0.count <= 2 }) {
                    let hasUsefulCommonPhrase = lowerSug.contains("of the") || lowerSug.contains("to the") || lowerSug.contains("in the")
                    if !hasUsefulCommonPhrase {
                        accepted = false; rejectionReason = "tinyGarbageAfterSpace"
                    }
                } else if ["ata", "anta", "yson", "ord", "pped"].contains(lowerSug) {
                    accepted = false; rejectionReason = "suffixLookingFragment"
                }
                
                if accepted {
                    let hasBoundary = suggestion.contains(" ") || suggestion.rangeOfCharacter(from: CharacterSet.punctuationCharacters) != nil
                    
                    if source == "early" {
                        if words.count == 1 {
                            if !hasBoundary {
                                accepted = false; rejectionReason = "immatureAfterSpaceCandidate"
                            } else if isShortCommonWord {
                                accepted = false; rejectionReason = "immatureAfterSpaceCandidate"
                            }
                        }
                    } else {
                        // For final fallback, reject if it's just a single tiny/short common word that doesn't mean anything by itself
                        if words.count == 1 && isShortCommonWord {
                            accepted = false; rejectionReason = "tooShortAfterSpace"
                        }
                    }
                }
            }
        }

        print("[VisibleUsefulnessGate] decision=\(accepted ? "accepted" : "rejected") mode=\(candidate.mode) reason=\(rejectionReason.isEmpty ? "valid" : rejectionReason)")
        
        LatencyInstrumentation.shared.setClassification(
            requestID: requestID,
            workID: workID,
            profile: "\(ModelProfile.current().family)",
            kind: candidate.mode,
            activeLine: activeLine,
            finalSuggestion: candidate.suggestion
        )
        if !accepted {
            LatencyInstrumentation.shared.renderExcluded(requestID: requestID, reason: rejectionReason)
        }

        if !accepted {
            print("[VisibleSuggestionAudit] requestID=\(requestID) decision=rejectedBeforeVisible mode=\(candidate.mode) activeLine='\(self.qualityAuditPreview(activeLine))' partialWord='\(partialWord)' rawOutput='\(self.qualityAuditPreview(candidate.rawOutput))' finalSuggestion='\(self.qualityAuditPreview(candidate.suggestion))' reason=\(rejectionReason)")
            if let dictData = try? JSONSerialization.data(withJSONObject: [
                "activeLine": activeLine,
                "rejectionReason": rejectionReason,
                "ghostVisible": false,
                "rawOutput": candidate.rawOutput,
                "finalSuggestion": candidate.suggestion,
                "epochSeconds": Date().timeIntervalSince1970
            ]), let jsonStr = String(data: dictData, encoding: .utf8) {
                print(jsonStr)
                fflush(stdout)
            }

            return
        }

        guard streamBuffer.tryUpdateDisplayedSuggestion(candidate.suggestion) else {
            streamBuffer.logSuppressedAfterVisible(requestID: requestID)
            return
        }

        LatencyInstrumentation.shared.firstUsable(requestID: requestID, workID: workID, textLen: candidate.finalLen)
        LatencyInstrumentation.shared.renderRequested(requestID: requestID, workID: workID, source: source, textLen: candidate.finalLen)

        let elapsedMs = (CFAbsoluteTimeGetCurrent() - candidate.createdAt) * 1000.0
        
        if source == "early" || source == "early-stable" {
            print("[AtomicGhost] earlyVisibleApply requestID=\(requestID) elapsedMs=\(String(format: "%.1f", elapsedMs))")
        } else {
            print("[AtomicGhost] finalFallback requestID=\(requestID) elapsedMs=\(String(format: "%.1f", elapsedMs))")
        }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            guard self.shouldRenderGenerationResult(requestID: requestID, workID: workID, source: "\(source)-main") else { return }
            
            self.atomicGhostLock.lock()
            let visibleCount = (self.atomicGhostVisibleApplyCountByRequestID[requestID] ?? 0) + 1
            self.atomicGhostLock.unlock()

            print("[VisibleSuggestionAudit] requestID=\(requestID) decision=visibleApplied mode=\(candidate.mode) activeLine='\(self.qualityAuditPreview(activeLine))' partialWord='\(partialWord)' rawOutput='\(self.qualityAuditPreview(candidate.rawOutput))' finalSuggestion='\(self.qualityAuditPreview(candidate.suggestion))' source=\(source) promptIsolationPolicy=inlineActiveTextOnly elapsedMs=\(String(format: "%.1f", elapsedMs)) visibleApplyCountForRequest=\(visibleCount)")

            if let dictData = try? JSONSerialization.data(withJSONObject: [
                "activeLine": activeLine,
                "visibleGhostText": candidate.suggestion,
                "ghostVisible": true,
                "rawOutput": candidate.rawOutput,
                "finalSuggestion": candidate.suggestion,
                "epochSeconds": Date().timeIntervalSince1970
            ]), let jsonStr = String(data: dictData, encoding: .utf8) {
                print(jsonStr)
                fflush(stdout)
            }
            
            self.applyAutocompleteOverlayText(
                candidate.suggestion,
                requestSnapshot: requestSnapshot,
                source: source,
                recordShown: recordShown
            )
        }

        // if source.hasPrefix("early") && cancellationToken.requestCancellation(reason: "atomic-visible-applied") {
        //     streamBuffer.logCancelledAfterVisible(requestID: requestID)
        // }
    }

    private func logAXHotPathCounts() {
        axHotPathLock.lock()
        let generation = axHotPathGetTextGenerationCount
        let stream = axHotPathGetTextStreamCount
        let render = axHotPathGetTextRenderCount
        axHotPathLock.unlock()
        print("[AXHotPath] getTextBeforeCaret count generation=\(generation) stream=\(stream) render=\(render)")
    }

    private func applyAutocompleteOverlayText(
        _ text: String,
        requestSnapshot: GenerationRequestSnapshot,
        source: String,
        recordShown: Bool = false
    ) {
        pendingCandidate = text
        pendingCandidatePrefix = requestSnapshot.canonicalTextBeforeCaret
        if !text.isEmpty {
            if recordShown {
                UsageStatsManager.shared.recordCompletionShown()
            }
            let geometry = requestSnapshot.resolveCaretRect(using: accessibilityMonitor)
            print("[AXHotPath] overlay geometry used cached=\(geometry.cached) requestID=\(requestSnapshot.requestID) source=\(source)")
            if let rect = geometry.rect {
                overlayWindowController?.moveOverlay(to: rect)
            }
            overlayWindowController?.updateAutocompleteText(text, requestID: requestSnapshot.requestID)
        } else {
            pendingCandidate = nil
            pendingCandidatePrefix = ""
            overlayWindowController?.updateAutocompleteText("", requestID: requestSnapshot.requestID)
        }
    }
    
    func setup(accessibilityMonitor: AccessibilityMonitor, overlayWindowController: OverlayWindowController) {
        self.accessibilityMonitor = accessibilityMonitor
        self.overlayWindowController = overlayWindowController
    }
    
    func getLastWord(from text: String) -> (word: String, range: NSRange)? {
        guard !text.isEmpty else { return nil }
        
        let chars = Array(text)
        var startIndex = chars.count
        
        var foundWordChar = false
        for i in (0..<chars.count).reversed() {
            let char = chars[i]
            let isWordChar = char.isLetter || char.isNumber || char == "'"
            if isWordChar {
                startIndex = i
                foundWordChar = true
            } else {
                break
            }
        }
        
        guard foundWordChar else { return nil }
        
        let word = String(chars[startIndex...])
        let startOffset = String(chars[..<startIndex]).utf16.count
        let length = word.utf16.count
        let range = NSRange(location: startOffset, length: length)
        
        return (word, range)
    }
    
    func getSpellCorrection(in text: String, lastWordRange: NSRange) -> String? {
        guard lastWordRange.length >= 4 else { return nil }
        
        let spellChecker = NSSpellChecker.shared
        let language = spellChecker.language()
        let word = (text as NSString).substring(with: lastWordRange)
        
        let startingAt = max(0, lastWordRange.location - 1)
        let misspelledRange = spellChecker.checkSpelling(
            of: text,
            startingAt: startingAt,
            language: language,
            wrap: false,
            inSpellDocumentWithTag: 0,
            wordCount: nil
        )
        
        let isMisspelled = (misspelledRange.location == lastWordRange.location && misspelledRange.length == lastWordRange.length)
        print("[TypeFlow-Debug] SpellCheck: Checking word '\(word)' (loc:\(lastWordRange.location) len:\(lastWordRange.length)) — misspelledRange: loc:\(misspelledRange.location) len:\(misspelledRange.length) — isMisspelled: \(isMisspelled)")
        guard isMisspelled else { return nil }
        
        if let corr = spellChecker.correction(forWordRange: lastWordRange, in: text, language: language, inSpellDocumentWithTag: 0), !corr.isEmpty {
            print("[TypeFlow-Debug] SpellCheck: correction() returned '\(corr)'")
            return corr
        }
        
        if let guesses = spellChecker.guesses(forWordRange: lastWordRange, in: text, language: language, inSpellDocumentWithTag: 0), !guesses.isEmpty {
            print("[TypeFlow-Debug] SpellCheck: guesses() returned \(guesses.prefix(5))")
            let wordLower = word.lowercased()
            let prefix2 = String(wordLower.prefix(2))
            if let bestMatch = guesses.first(where: { $0.lowercased().hasPrefix(prefix2) }) {
                return bestMatch
            }
            let prefix1 = String(wordLower.prefix(1))
            if let firstMatch = guesses.first(where: { $0.lowercased().hasPrefix(prefix1) }) {
                return firstMatch
            }
        }
        
        print("[TypeFlow-Debug] SpellCheck: No correction or guesses found for '\(word)'")
        return nil
    }
    
    func getGhostText(misspelled: String, correction: String) -> String {
        let misLower = misspelled.lowercased()
        let corrLower = correction.lowercased()
        if corrLower.hasPrefix(misLower) {
            return String(correction.dropFirst(misspelled.count))
        } else {
            return correction
        }
    }
    
    private func calculateDeleteCount(activeLine: String, misspelled: String) -> Int {
        if let range = activeLine.range(of: misspelled, options: [.backwards, .caseInsensitive]) {
            // Ensure bounds check when misspelled word is at index 0
            if range.lowerBound == activeLine.startIndex {
                return activeLine.utf16.distance(from: range.lowerBound, to: activeLine.endIndex)
            }
            return activeLine.utf16.distance(from: range.lowerBound, to: activeLine.endIndex)
        }
        return misspelled.count
    }
    
    private func getCompletedWord(from text: String) -> (word: String, delimiter: String, range: NSRange)? {
        guard !text.isEmpty else { return nil }
        
        let chars = Array(text)
        let lastChar = chars.last!
        
        let delimiters: Set<Character> = [" ", ".", ",", "!", "?"]
        guard delimiters.contains(lastChar) else { return nil }
        
        let delimiter = String(lastChar)
        
        var startIndex = chars.count - 1
        var foundWordChar = false
        
        for i in (0..<(chars.count - 1)).reversed() {
            let char = chars[i]
            let isWordChar = char.isLetter || char.isNumber || char == "'"
            if isWordChar {
                startIndex = i
                foundWordChar = true
            } else {
                break
            }
        }
        
        guard foundWordChar else { return nil }
        
        let word = String(chars[startIndex..<(chars.count - 1)])
        let startOffset = String(chars[..<startIndex]).utf16.count
        let length = word.utf16.count
        let range = NSRange(location: startOffset, length: length)
        
        return (word, delimiter, range)
    }
    
    func handleAsynchronousSpellcheck(bufferSnapshot: String) -> (misspelledLength: Int, correction: String)? {
        guard SettingsManager.shared.autoCorrectEnabled else { return nil }
        if let completedWordInfo = getCompletedWord(from: bufferSnapshot) {
            let word = completedWordInfo.word
            let wordRange = completedWordInfo.range
            let delimiter = completedWordInfo.delimiter
            
            if word.count >= 4, let correction = getSpellCorrection(in: bufferSnapshot, lastWordRange: wordRange) {
                print("[TypeFlow-Debug] Asynchronous auto-correct triggered: '\(word)' -> '\(correction)'")
                
                // Use the exact word length for deletion count instead of range distance to end of line
                let deleteCount = word.count
                
                DispatchQueue.main.async {
                    self.workController.cancelAll()
                    
                    // Buffer Alignment Protection for Screen UI: check if user typed anything while we were calculating
                    let currentBufferCount = self.accessibilityMonitor?.keystrokeBuffer.count ?? bufferSnapshot.count
                    let delta = currentBufferCount - bufferSnapshot.count
                    
                    guard delta >= 0 else {
                        print("[TypeFlow-Debug] SpellCheck UI: Aborting, user deleted text during async resolution.")
                        return
                    }
                    
                    // We must delete the word (deleteCount) PLUS the delimiter PLUS the newly typed chars
                    TextInjector.shared.injectBackspaces(count: deleteCount + delimiter.count + delta)
                    
                    // Re-inject the new characters after the correction
                    let newlyTyped = delta > 0 ? String(self.accessibilityMonitor?.keystrokeBuffer.suffix(delta) ?? "") : ""
                    
                    // Inject the correction and explicitly append the trailing space via pasteboard + newly typed
                    let trailingSpace = (delimiter == " ") ? " " : ""
                    TextInjector.shared.injectCharByChar(text: correction + delimiter + trailingSpace + newlyTyped)
                    
                    self.clearCompletion()
                }
                
                let correctedLine = String(bufferSnapshot.dropLast(deleteCount + delimiter.count)) + correction + delimiter
                print("[TypeFlow-Debug] Logging auto-corrected sentence to history: '\(correctedLine)'")
                TypingHistoryManager.shared.logSentenceFromText(correctedLine)
                return (word.count, correction + delimiter)
            }
        }
        return nil
    }
    
    func onTextChanged(bufferFallback: String = "") {
        autoreleasepool {
            if isRewrite || isSmartReply { return }
            if TextInjector.shared.syntheticEventWithinLast(milliseconds: 1500.0) {
                print("[TypeFlow-Debug] onTextChanged: ignoring text change because of recent synthetic injection")
                return
            }

        // ── Dynamic Typing Invalidation / Prefix Consumption ──────────────────────────────────────
        // If an overlay is active, verify if user typed text matches the active prediction.
        // If so, consume the matching prefix and keep the remaining ghost visible.
        if let ghost = displayedCompletion, !ghost.isEmpty {
            let prev = displayedCompletionPrefix
            let curr = bufferFallback

            // Extract the active line (the last line) of prev and curr to ensure
            // matching is completely independent of whether they contain preceding lines.
            let prevActive = prev.components(separatedBy: .newlines).last ?? ""
            let currActive = curr.components(separatedBy: .newlines).last ?? ""
            let expectedFullActive = prevActive + ghost

            // Primary match: currActive is prevActive + some typed chars, and expectedFullActive starts with currActive
            let typedChars = currActive.count > prevActive.count && currActive.hasPrefix(prevActive) ? String(currActive.dropFirst(prevActive.count)) : ""
            var matches = (currActive == prevActive) || (currActive.count > prevActive.count && currActive.hasPrefix(prevActive) && expectedFullActive.lowercased().hasPrefix(currActive.lowercased()))

            // AX-lag fallback: if AX text hasn't updated yet or has skipped events, and keystroke buffer
            // has one or more chars that match the ghost, treat as a match using the keystroke buffer.
            var effectiveCurrActive = currActive
            if !matches, let ksBuffer = accessibilityMonitor?.keystrokeBuffer {
                let ksBufferActive = ksBuffer.components(separatedBy: .newlines).last ?? ""
                if ksBufferActive.count > prevActive.count,
                   ksBufferActive.hasPrefix(prevActive),
                   expectedFullActive.lowercased().hasPrefix(ksBufferActive.lowercased()) {
                    // Keystroke buffer already has the new chars; AX is just lagging.
                    // Consume using keystroke buffer as source of truth.
                    effectiveCurrActive = ksBufferActive
                    matches = true
                }
            }

            // AX-lag catch-up: if effectiveCurrActive is behind prevActive but is still a valid prefix
            // of expectedFullActive, this is just AX lag. Keep matches = true, and do not advance or clear.
            if !matches && effectiveCurrActive.count < prevActive.count && expectedFullActive.lowercased().hasPrefix(effectiveCurrActive.lowercased()) {
                matches = true
            }

            let typedCharsEffective = effectiveCurrActive.count > prevActive.count && effectiveCurrActive.hasPrefix(prevActive) ? String(effectiveCurrActive.dropFirst(prevActive.count)) : typedChars
            let advanced = matches ? String(expectedFullActive.dropFirst(effectiveCurrActive.count)) : ""

            let diagnostic: [String: Any] = [
                "epochSeconds": Date().timeIntervalSince1970,
                "eventPhase": "onTextChanged",
                "prefixConsumptionActive": matches,
                "typedChars": typedCharsEffective,
                "displayedCompletionBefore": ghost,
                "displayedCompletionAfter": matches ? advanced : "",
                "prefixMatched": matches,
                "consumedChars": matches ? typedCharsEffective : "",
                "consumedToEmpty": matches && advanced.isEmpty,
                "ghostKeptVisible": matches && !advanced.isEmpty,
                "llmRequestSuppressed": matches,
                "debounceSuppressed": matches,
                "staleRenderSuppressed": matches,
                "axLagHandled": matches && effectiveCurrActive != currActive,
                "divergenceDetected": !matches,
                "reason": matches ? (advanced.isEmpty ? "ghostFullyConsumed" : "prefixMatched") : "divergence"
            ]

            if let dictData = try? JSONSerialization.data(withJSONObject: diagnostic),
               let jsonStr = String(data: dictData, encoding: .utf8) {
                print("[PrefixConsumptionDiagnostic] \(jsonStr)")
                fflush(stdout)
            }

            if matches {
                let isAXLagCatchUp = prevActive.lowercased().hasPrefix(effectiveCurrActive.lowercased()) && effectiveCurrActive.count < prevActive.count
                if isAXLagCatchUp {
                    // Keep ghost visible, abort active generation since user is typing, but do NOT schedule a new one
                    requestActiveGenerationAbort(reason: "new-input")
                    return
                }

                let finalPrefix = prev + typedCharsEffective
                lastBufferSnapshot = finalPrefix
                displayedCompletionPrefix = finalPrefix
                pendingCandidatePrefix = finalPrefix

                if advanced.isEmpty {
                    // Ghost fully consumed by typing. Clean up ghost state.
                    displayedCompletion = nil
                    displayedCompletionPrefix = ""
                    pendingCandidate = nil
                    pendingCandidatePrefix = ""
                    accessibilityMonitor?.setAcceptTapNeededForVisibleCompletion(false, reason: "ghostFullyConsumed")
                    overlayWindowController?.updateGhostText("", isStale: false)

                    // Schedule a fresh generation from the new text so the user
                    // doesn't get stuck after manually typing the full suggestion.
                    LatencyInstrumentation.shared.onTextChanged(bufferLen: finalPrefix.count)
                    lastBufferSnapshot = finalPrefix
                    let debounceDelayMs = 25  // short idle after full-consumption
                    let scheduledWorkID = workController.replaceDebouncedWork(delayMilliseconds: debounceDelayMs) { [weak self] workID in
                        _ = self?.debounceAuditMarkFired(workID: workID)
                        LatencyInstrumentation.shared.debounceFired(workID: workID)
                        print("[TypeFlow-Debug] Debounce timer fired (post ghost-consumed)!")
                        self?.triggerGeneration(with: nil, workID: workID)
                    }
                    debounceAuditScheduled(text: finalPrefix, textHash: debounceAuditHash(finalPrefix), workID: scheduledWorkID, delayMs: debounceDelayMs)
                    print("[PrintableInputDiagnostic] ghostFullyConsumed — scheduled fresh generation workID=\(scheduledWorkID)")
                    return
                } else {
                    displayedCompletion = advanced
                    pendingCandidate = advanced
                    if !typedCharsEffective.isEmpty {
                        overlayWindowController?.replaceGhostTextAfterAcceptance(inserted: typedCharsEffective, remainder: advanced, source: "typedPrefix")
                    }
                }

                // Keep ghost visible, abort active generation since user is typing, but do NOT schedule a new one
                requestActiveGenerationAbort(reason: "new-input")
                return
            } else {
                // User diverged from ghost text — clear state immediately and hide overlay.
                // Do NOT show stale grey ghost; fall through to the normal debounce path so a
                // fresh generation starts quickly.
                displayedCompletion = nil
                displayedCompletionPrefix = ""
                pendingCandidate = nil
                pendingCandidatePrefix = ""
                workController.cancelAll()
                overlayWindowController?.updateGhostText("", isStale: false)
            }
        }
        
        LatencyInstrumentation.shared.onTextChanged(bufferLen: bufferFallback.count)
        let debounceAudit = debounceAuditTextChanged(bufferFallback)
        if debounceAudit.shouldSkip {
            return
        }
        // Suppressed: print("[TypeFlow-Debug] onTextChanged called")
        invalidateGenerationResults(reason: "text-changed", bufferSnapshot: bufferFallback)
        overlayWindowController?.dropPendingAutocompleteRenders(reason: "textChanged")
        requestActiveGenerationAbort(reason: "new-input")
        
        if workController.isGenerationRunning {
            // Do NOT return here — the active generation was already cancelled above via
            // requestActiveGenerationAbort. The debounce must be scheduled so the latest
            // typed text wins. replaceGenerationWork will cancel the old Task when the
            // debounce fires and a new generation starts.
            print("[TypeFlow-Debug] onTextChanged: background generation running but was cancelled — scheduling debounce for new input.")
        }
        if isSuppressedUntilNextTyping {
            let activeLine = bufferFallback.trimmingCharacters(in: .whitespacesAndNewlines)
            if !activeLine.isEmpty {
                print("[TypeFlow-Debug] Resetting submission suppression flag on new keystroke.")
                isSuppressedUntilNextTyping = false
            }
        }
        
        lastBufferSnapshot = bufferFallback
        
        // Clear existing completion state immediately when user types, but leave UI visible
        if debounceAuditPendingBeforeSchedule() {
            print("[DebounceAudit] cancelled previous debounce reason=newer-text")
        }
        clearCompletion(hideUI: false)

        
        if let bundleId = NSWorkspace.shared.frontmostApplication?.bundleIdentifier {
            if SettingsManager.shared.isAppExcluded(bundleId: bundleId) {
                clearCompletion()
                return
            }
        }
        
        // For the spacebar spellcheck, isolate the extraction strictly to the current word buffer.
        // We defer the heavy kAXValue polling to the debounce timer's background thread to prevent energy regression.
        let activeLine = bufferFallback
        
        TypingHistoryManager.shared.logSentenceFromText(activeLine)
        
        // 1. Check if the user just typed a completed word followed by a delimiter
        if let completedWordInfo = getCompletedWord(from: activeLine) {
            let word = completedWordInfo.word
            let wordRange = completedWordInfo.range
            let delimiter = completedWordInfo.delimiter
            
            if word.count >= 4, let correction = getSpellCorrection(in: activeLine, lastWordRange: wordRange) {
                print("[TypeFlow-Debug] Completed word spell correction found: '\(word)' -> '\(correction)'")
                
                // Cancel any pending LLM generation tasks
                workController.cancelAll()
                
                if SettingsManager.shared.autoCorrectEnabled {
                    print("[TypeFlow-Debug] Auto-correct is enabled. Automatically correcting '\(word)' to '\(correction)'")
                    let deleteCount = calculateDeleteCount(activeLine: activeLine, misspelled: word)
                    let correctedLine = String(activeLine.dropLast(deleteCount)) + correction + delimiter
                    print("[TypeFlow-Debug] Logging auto-corrected sentence to history: '\(correctedLine)'")
                    TypingHistoryManager.shared.logSentenceFromText(correctedLine)
                    
                    DispatchQueue.main.async {
                        TextInjector.shared.injectBackspaces(count: deleteCount)
                        let trailingSpace = (delimiter == " ") ? " " : ""
                        TextInjector.shared.injectCharByChar(text: correction + delimiter + trailingSpace)
                        self.clearCompletion()
                    }
                    return
                } else {
                    let enableSpellcheckGhosts = true
                    if !enableSpellcheckGhosts {
                        print("[SpellcheckGhost] suppressed reason=disabledForInlineAutocomplete")
                        return
                    }
                    print("[SpellcheckGhost] visibleApplied")
                    // Show it as orange ghost text suggestion
                    activeSpellCorrection = (misspelled: word, corrected: correction)
                    let ghostText = getGhostText(misspelled: word, correction: correction)
                    // Fetch caret rect lazily on the main thread just before showing the overlay —
                    // never during the hot typing loop.
                    DispatchQueue.main.async {
                        self.pendingCandidate = ghostText
                        self.pendingCandidatePrefix = activeLine
                        if !ghostText.isEmpty {
                            if let rect = self.accessibilityMonitor?.getCurrentCaretRect() {
                                self.overlayWindowController?.moveOverlay(to: rect)
                            }
                            self.overlayWindowController?.updateText(ghostText, isSpellCorrection: true)
                        } else {
                            self.overlayWindowController?.updateText("", isSpellCorrection: true)
                        }
                    }
                    return
                }
            }
        }
        
        // 2. If it's not a completed word with delimiter, check if it's an inline word being typed
        if let lastWordInfo = getLastWord(from: activeLine) {
            let word = lastWordInfo.word
            let wordRange = lastWordInfo.range
            
            // Only check inline if the word is at least 4 characters long
            if word.count >= 4 {
                // Check completions for partial word to see if it is a prefix of a valid word
                let completions = NSSpellChecker.shared.completions(
                    forPartialWordRange: NSRange(location: 0, length: word.utf16.count),
                    in: word,
                    language: NSSpellChecker.shared.language(),
                    inSpellDocumentWithTag: 0
                ) ?? []
                
                // If it is a prefix of a valid word (completions is not empty), we STOP using NSSpellChecker
                // and let it fall through to the LLM completion pipeline!
                if completions.isEmpty {
                    let correction = getSpellCorrection(in: activeLine, lastWordRange: wordRange)
                    print("[TypeFlow-Debug] SpellCheck: Checking word '\(word)' - result: \(correction ?? "nil")")
                    if let correction = correction {
                        print("[TypeFlow-Debug] Inline definite typo spell correction found: '\(word)' -> '\(correction)'")
                        // Cancel any pending LLM generation tasks
                        workController.cancelAll()
                        
                        let enableSpellcheckGhosts = true
                        if !enableSpellcheckGhosts {
                            print("[SpellcheckGhost] suppressed reason=disabledForInlineAutocomplete")
                            return
                        }
                        print("[SpellcheckGhost] visibleApplied")
                        
                        activeSpellCorrection = (misspelled: word, corrected: correction)
                        
                        let ghostText = getGhostText(misspelled: word, correction: correction)
                        
                        // Always show orange ghost text for inline mid-word typos so the user
                        // has visual feedback — even when Auto-correct is enabled.
                        // (Silent auto-fix only fires on the delimiter-triggered path above.)
                        // Fetch caret rect lazily on the main thread just before showing the overlay —
                        // never during the hot typing loop.
                        DispatchQueue.main.async {
                            self.pendingCandidate = ghostText
                            self.pendingCandidatePrefix = activeLine
                            if !ghostText.isEmpty {
                                if let rect = self.accessibilityMonitor?.getCurrentCaretRect() {
                                    self.overlayWindowController?.moveOverlay(to: rect)
                                }
                                self.overlayWindowController?.updateText(ghostText, isSpellCorrection: true)
                            } else {
                                self.overlayWindowController?.updateText("", isSpellCorrection: true)
                            }
                        }
                        return
                    }
                }
            }
        }
        
        // Adaptive debounce: 25ms when stable (after-space or slow typing), 50ms for rapid mid-word.
        // 25ms is sufficient to avoid duplicate generation from keyDown/keyUp for the same text.
        let now = Date()
        let keystrokeInterval = now.timeIntervalSince(lastKeystrokeTime)
        lastKeystrokeTime = now
        let debounceInterval: TimeInterval = keystrokeInterval < 0.12 ? 0.050 : 0.025
        // Suppressed: print("[TypeFlow-Debug] Adaptive debounce...")
        
        NotificationCenter.default.post(name: Notification.Name("UserDidType"), object: nil)
        
        let debounceDelayMs = Int(debounceInterval * 1000)
        let scheduledWorkID = workController.replaceDebouncedWork(delayMilliseconds: debounceDelayMs) { [weak self] workID in
            _ = self?.debounceAuditMarkFired(workID: workID)
            LatencyInstrumentation.shared.debounceFired(workID: workID)
            print("[TypeFlow-Debug] Debounce timer fired!")
            self?.triggerGeneration(workID: workID)
        }
        debounceAuditScheduled(text: bufferFallback, textHash: debounceAudit.textHash, workID: scheduledWorkID, delayMs: debounceDelayMs)
        LatencyInstrumentation.shared.debounceScheduled(workID: scheduledWorkID, delayMs: debounceDelayMs)
        }
    }
    
    private func triggerGeneration(with text: String? = nil, workID: UInt64? = nil) {
        guard SettingsManager.shared.enableAutocomplete else {
            print("[TypeFlow-Debug] triggerGeneration: Autocomplete disabled, skipping.")
            return
        }
        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            guard let self = self else { return }
            LatencyInstrumentation.shared.generationRequested(workID: workID)
            
            if self.isSuppressedUntilNextTyping {
                print("[TypeFlow-Debug] triggerGeneration aborted due to isSuppressedUntilNextTyping.")
                return
            }
            
            self.requestCount += 1
            let currentRSS = self.getRSSMemory()
            if self.initialRSS == 0.0 { self.initialRSS = currentRSS }
            if self.requestCount == 5 && self.warmRSS == 0.0 { self.warmRSS = currentRSS }
            if currentRSS > self.maxRSS { self.maxRSS = currentRSS }
            let deltaFromWarm = self.warmRSS > 0.0 ? currentRSS - self.warmRSS : 0.0
            
            let historyCounts = UniversalContextManager.shared.contextHistory.count
            let snapshotCounts = 1
            let activeTaskCount = (self.workController.isGenerationRunning ? 1 : 0)
            // Do NOT access overlayWindow.contentView from a background thread — Main Thread Checker violation.
            // overlaySubviewCount() is a main-thread method on OverlayWindowController; skip here.
            let subviewCount = -1  // unavailable off main thread
            
            print("[MemoryDiagnostic] rssMB=\(String(format: "%.1f", currentRSS)) deltaFromWarmMB=\(String(format: "%.1f", deltaFromWarm)) requestCount=\(self.requestCount) historyCounts=\(historyCounts) snapshotCounts=\(snapshotCounts) activeTaskCount=\(activeTaskCount) overlaySubviewCount=\(subviewCount)")
            
            print("[TypeFlow-Debug] triggerGeneration started. Cancelling any previous inflight task...")
            
            if let providedText = text {
                logContextAudit("triggerGeneration source=providedText providedTextLen=\(providedText.count) providedText='\(contextAuditPreview(providedText))' liveBufferLen=0")
                let snapshot = PredictionSnapshot(rawTextBeforeCaret: providedText, source: .providedText, liveBuffer: "")
                self.continueGeneration(snapshot: snapshot)
            } else {
                LatencyInstrumentation.shared.axFetchStart(workID: workID)
                self.recordAXHotPathGetTextRead(phase: "generation")
                let textSnapshot = self.accessibilityMonitor?.getTextBeforeCaretSnapshot()
                let axText = textSnapshot?.text ?? ""
                let axSource = textSnapshot?.source ?? .none
                LatencyInstrumentation.shared.axFetchEnd(workID: workID, source: axSource.rawValue, textLen: axText.count)
                let bufferAfterAX = self.accessibilityMonitor?.keystrokeBuffer ?? ""
                logContextAudit("triggerGeneration afterAX axSource=\(axSource.rawValue) axTextLen=\(axText.count) axText='\(contextAuditPreview(axText))' keystrokeBufferLen=\(bufferAfterAX.count) keystrokeBuffer='\(contextAuditPreview(bufferAfterAX))'")
                
                let liveBuffer = self.accessibilityMonitor?.keystrokeBuffer ?? ""
                let snapshot = PredictionSnapshot(
                    rawTextBeforeCaret: !axText.isEmpty ? axText : liveBuffer,
                    source: !axText.isEmpty ? axSource : .keystrokeBufferFallback,
                    liveBuffer: liveBuffer
                )
                let finalLine = snapshot.rawTextBeforeCaret
                
                DispatchQueue.main.async {
                    self.logContextAudit("triggerGeneration dispatch direct finalLineSource=\(snapshot.source.rawValue) axTextLen=\(axText.count) liveBufferLen=\(liveBuffer.count) finalLineLen=\(finalLine.count) finalLine='\(self.contextAuditPreview(finalLine))' liveBuffer='\(self.contextAuditPreview(liveBuffer))'")
                    self.continueGeneration(snapshot: snapshot)
                }
            }
        }
    }
    
    // MARK: - Page context direct continuation matcher
    //
    // Checks whether the user's active text is a verbatim prefix of text in the cached page.
    // If so, returns the continuation directly from the cache — no LLM needed.
    // Requirements:
    //   - 12+ normalized chars of exact suffix match, OR 3+ meaningful words match
    //   - Mid-word: if high-confidence, handles the partial-word boundary
    //   - Returns prose: next 3–8 words capped at 90 chars / code: 120 chars

    struct PageDirectCandidate {
        let suggestion: String
        let matchChars: Int
        let matchWords: Int
        let matchOffset: Int         // byte offset in page text where match was found
        let pageDirectSuffix: String // the raw page text after match
        let latencyMs: Double
    }

    func findPageDirectCandidate(activeLine: String, pageText: String) -> PageDirectCandidate? {
        let t0 = CFAbsoluteTimeGetCurrent()
        guard !activeLine.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !pageText.isEmpty else { return nil }

        // Normalize: collapse whitespace, replace NBSP, smart quotes → ASCII
        func normalize(_ s: String) -> String {
            s.replacingOccurrences(of: "\u{00A0}", with: " ")
             .replacingOccurrences(of: "\u{2018}", with: "'")
             .replacingOccurrences(of: "\u{2019}", with: "'")
             .replacingOccurrences(of: "\u{201C}", with: "\"")
             .replacingOccurrences(of: "\u{201D}", with: "\"")
             .replacingOccurrences(of: "  ", with: " ")
        }

        let normPage = normalize(pageText)
        let normActive = normalize(activeLine)

        // Extract the active line suffix (last line only, to avoid multi-paragraph false matches)
        let activeLastLine = normActive.components(separatedBy: "\n").last ?? normActive
        let trimmedLine = activeLastLine.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Safety check: require at least 2 non-whitespace characters to prevent matching single spaces/letters
        guard trimmedLine.count >= 2 else { return nil }

        // Identify alphanumeric suffix (representing current partial word typing)
        let trimmedLineChars = Array(trimmedLine)
        var i = trimmedLineChars.count - 1
        let wordChars = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "'-"))
        while i >= 0 {
            let char = trimmedLineChars[i]
            if let scalar = char.unicodeScalars.first, wordChars.contains(scalar) {
                i -= 1
            } else {
                break
            }
        }
        let partialWord = String(trimmedLineChars[(i + 1)...])

        // Determine if we are mid-word (ends in alphanumeric char)
        let lastChar = trimmedLine.last ?? " "
        let isMidWord = !partialWord.isEmpty && (lastChar.isLetter || lastChar.isNumber)

        var suffixesToTry: [(suffix: String, droppedText: String)] = []

        if isMidWord {
            // Try verbatim first
            suffixesToTry.append((trimmedLine, ""))
            // Try dropping characters from partialWord one by one
            let partialLen = partialWord.count
            if partialLen >= 1 {
                for drop in 1...partialLen {
                    let suffixLen = trimmedLine.count - drop
                    if suffixLen >= 2 {
                        let suffix = String(trimmedLine.prefix(suffixLen))
                        let dropped = String(trimmedLine.suffix(drop))
                        suffixesToTry.append((suffix, dropped))
                    }
                }
            }
        } else {
            // After space/punctuation: try longest suffix first, down to 6 chars
            let maxLen = min(trimmedLine.count, 80)
            if maxLen >= 6 {
                for len in stride(from: maxLen, through: 6, by: -4) {
                    let suffix = String(trimmedLine.suffix(len))
                    suffixesToTry.append((suffix, ""))
                }
            }
        }

        let lowerPage = normPage.lowercased()

        for (suffix, droppedText) in suffixesToTry {
            guard suffix.count >= 6 else { continue }
            let lowerSuffix = suffix.lowercased()

            // Find last occurrence of suffix in page
            guard let matchRange = lowerPage.range(of: lowerSuffix, options: .backwards) else {
                continue
            }

            // Calculate match quality
            let matchChars = suffix.count
            let matchWords = suffix.components(separatedBy: .whitespaces).filter { !$0.isEmpty }.count

            // Require minimum confidence: 12+ chars OR 3+ words
            guard matchChars >= 12 || matchWords >= 3 else { continue }

            // Get the page text after the match
            let matchEnd = normPage.index(normPage.startIndex, offsetBy: normPage.distance(from: normPage.startIndex, to: matchRange.upperBound), limitedBy: normPage.endIndex) ?? normPage.endIndex
            let pageAfterMatch = String(normPage[matchEnd...])

            var wordRemainder = ""
            var remainingPageText = pageAfterMatch

            if !droppedText.isEmpty {
                // Get the next word in the page starting at pageAfterMatch
                let pageWordPrefix = pageAfterMatch.prefix(while: { $0.isLetter || $0.isNumber || $0 == "'" || $0 == "-" })
                let pageWord = String(pageWordPrefix)

                // Must start with droppedText (case-insensitive)
                guard pageWord.lowercased().hasPrefix(droppedText.lowercased()) else {
                    continue
                }

                // Word remainder is the rest of pageWord after droppedText
                let droppedLen = droppedText.count
                if pageWord.count >= droppedLen {
                    let index = pageWord.index(pageWord.startIndex, offsetBy: droppedLen)
                    wordRemainder = String(pageWord[index...])
                }
                
                remainingPageText = String(pageAfterMatch.dropFirst(pageWord.count))
            }

            guard !(wordRemainder + remainingPageText).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                continue
            }

            // Determine if the continuation is code or prose
            let isCode = remainingPageText.contains("{") || remainingPageText.contains("(") ||
                         remainingPageText.contains("->") || remainingPageText.contains("=>")
            let capLen = isCode ? 120 : 90

            // Combine remainder and subsequent text
            var continuation = (wordRemainder + remainingPageText).trimmingCharacters(in: .init(charactersIn: " \t"))
            
            // Take next N words up to capLen
            let words = continuation.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            var built = ""
            for word in words.prefix(isCode ? 20 : 8) {
                let candidate = built.isEmpty ? word : built + " " + word
                if candidate.count > capLen { break }
                built = candidate
            }
            continuation = built
            
            guard !continuation.isEmpty else { continue }

            let suggestion = continuation
            guard !suggestion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }

            let matchOffset = normPage.distance(from: normPage.startIndex, to: matchRange.lowerBound)
            let latencyMs = (CFAbsoluteTimeGetCurrent() - t0) * 1000.0

            return PageDirectCandidate(
                suggestion: suggestion,
                matchChars: matchChars,
                matchWords: matchWords,
                matchOffset: matchOffset,
                pageDirectSuffix: String(pageAfterMatch.prefix(200)),
                latencyMs: latencyMs
            )
        }

        return nil
    }

    private func continueGeneration(snapshot: PredictionSnapshot) {

        let canonicalContext = canonicalizePredictionSnapshot(snapshot)
        syncFallbackBufferIfAuthoritative(canonicalContext, source: snapshot.source)
        let activeLine = canonicalContext.canonicalTextBeforeCaret
        let keystrokeBuffer = snapshot.liveBuffer
        logContextAudit("continueGeneration input source=\(snapshot.source.rawValue) canonicalTextLen=\(activeLine.count) canonicalText='\(contextAuditPreview(activeLine))' rawTextLen=\(snapshot.rawTextBeforeCaret.count) liveBufferLen=\(keystrokeBuffer.count) liveBuffer='\(contextAuditPreview(keystrokeBuffer))'")
        guard !activeLine.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            print("[TypeFlow-Debug] Active line is empty, skipping generation.")
            return
        }
        
        // Guard: do not complete placeholder text like "Ask anything" or "Type a message"
        let lowerActive = activeLine.lowercased()
        if lowerActive.contains("ask anything") || lowerActive.contains("type a message") {
            print("[TypeFlow-Debug] skipping generation on placeholder text.")
            return
        }
        
        let bundleId = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "unknown"
        
        let effectiveConfig = SettingsManager.shared.getEffectiveConfig(for: bundleId)
        
        if !effectiveConfig.isEnabled {
            print("[TypeFlow-Debug] Completions disabled for \(bundleId), skipping.")
            return
        }
        
        // Snippets check
        let snippets = SettingsManager.shared.getSnippets()
        for (key, value) in snippets {
            if (key.hasPrefix("/") || key.hasPrefix(";")) && hasWordBoundaryBeforeSuffix(activeLine: activeLine, suffix: key) {
                print("[TypeFlow-Debug] Snippet matched: '\(key)' -> '\(value)'")
                activeSnippetKey = key
                
                let resolved = resolveSnippetPlaceholders(value)
                let (displayText, _) = processCursorPlaceholder(resolved)
                
                DispatchQueue.main.async {
                    self.pendingCandidate = value
                    self.pendingCandidatePrefix = activeLine
                    self.overlayWindowController?.updateText(displayText)
                }
                return
            }
        }
        activeSnippetKey = nil

        // ── Direct page-context continuation path ─────────────────────────────────
        // Before scheduling the LLM, check if the user is typing verbatim text from
        // the cached page. If so, serve the continuation directly from cache.
        // This is instant (<20ms) and wins over the LLM path when confident.
        let fullActiveLine = canonicalContext.canonicalTextBeforeCaret
        let effectiveLiveBuffer = canonicalContext.liveBufferForPrompt
        let pageText = ScreenContextManager.shared.cachedContext?.text ?? ""
        let pageDirectAttempted = !pageText.isEmpty

        if pageDirectAttempted {
            let directCandidate = findPageDirectCandidate(activeLine: fullActiveLine, pageText: pageText)
            let used = directCandidate != nil

            let rejectReason = used ? "none" : "noHighConfidenceMatch"
            print("[PageDirectCandidate] attempt=\(pageDirectAttempted) used=\(used) matchChars=\(directCandidate?.matchChars ?? 0) matchWords=\(directCandidate?.matchWords ?? 0) matchOffset=\(directCandidate?.matchOffset ?? -1) pageDirectSuffix='\(directCandidate?.pageDirectSuffix.prefix(60) ?? "")' rejectReason=\(rejectReason) latencyMs=\(String(format: "%.1f", directCandidate?.latencyMs ?? 0.0))")

            if let dc = directCandidate {
                let suggestion = dc.suggestion
                let requestID = beginResultRequest(activeLine: fullActiveLine)
                LatencyInstrumentation.shared.requestStarted(requestID: requestID, workID: workController.currentWorkID)
                print("[Stage1B] pageContextContinuation candidateKind=pageContextContinuation requestID=\(requestID) matchChars=\(dc.matchChars) suggestion='\(suggestion.prefix(60))'")
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.pendingCandidate = suggestion
                    self.pendingCandidatePrefix = fullActiveLine
                    self.displayedCompletion = suggestion
                    self.displayedCompletionPrefix = fullActiveLine
                    self.lastBufferSnapshot = self.accessibilityMonitor?.keystrokeBuffer ?? ""
                    let caretRect = self.accessibilityMonitor?.getCurrentCaretRect()
                    if let rect = caretRect {
                        self.overlayWindowController?.moveOverlay(to: rect)
                    }
                    self.overlayWindowController?.updateText(suggestion)
                    self.accessibilityMonitor?.setAcceptTapNeededForVisibleCompletion(true, reason: "pageContextContinuation")
                    print("[VisibleSuggestionAudit] requestID=\(requestID) decision=visibleApplied mode=pageContextContinuation activeLine='\(fullActiveLine.prefix(40))' finalSuggestion='\(suggestion)' source=pageContextContinuation promptIsolationPolicy=fullContext elapsedMs=1.0")
                }
                return
            }

        }
        // ── End direct page-context path ──────────────────────────────────────────


        logContextAudit("continueGeneration resolved source=\(snapshot.source.rawValue) didAppendLiveBuffer=\(canonicalContext.didAppendLiveBuffer) appendReason='\(canonicalContext.appendReason)' textBeforeCaretLen=\(fullActiveLine.count) textBeforeCaret='\(contextAuditPreview(fullActiveLine))' effectiveLiveBufferLen=\(effectiveLiveBuffer.count) effectiveLiveBuffer='\(contextAuditPreview(effectiveLiveBuffer))' originalRawTextLen=\(snapshot.rawTextBeforeCaret.count) originalLiveBufferLen=\(keystrokeBuffer.count)")
        
        self.generationStartCaretText = fullActiveLine
        let resultRequestID = beginResultRequest(activeLine: fullActiveLine)
        let generationStartText = fullActiveLine
        
        // Explicitly cancel any inflight task before creating a new one.
        let workID = workController.currentWorkID
        LatencyInstrumentation.shared.requestStarted(requestID: resultRequestID, workID: workID)
        debounceAuditFired(requestID: resultRequestID, workID: workID)
        let requestSnapshot = GenerationRequestSnapshot(
            requestID: resultRequestID,
            workID: workID,
            canonicalTextBeforeCaret: fullActiveLine,
            source: snapshot.source,
            textHash: debounceAuditHash(fullActiveLine)
        )
        print("[AXHotPath] generation snapshot captured requestID=\(resultRequestID) textHash=\(requestSnapshot.textHash) source=\(snapshot.source.rawValue)")
        logAXHotPathCounts()
        let generationCancellationToken = LlamaGenerationCancellationToken(requestID: resultRequestID, workID: workID)
        installGenerationCancellationToken(generationCancellationToken)
        print("[Stage1B] generation started requestID=\(resultRequestID) workID=\(workID)")
        resetAtomicGhostVisibleApplyCount(requestID: resultRequestID)
        let atomicGhostStreamBuffer = AtomicGhostStreamBuffer()
        
        workController.replaceGenerationWork(for: workID) { [weak self] in
            guard let self = self else { return }
            defer {
                self.clearGenerationCancellationTokenIfCurrent(generationCancellationToken)
                self.debounceAuditGenerationFinished(workID: workID)
                self.workController.setGenerationFinished()
            }
            
            // If this task was cancelled while waiting, abort early
            if Task.isCancelled || !self.workController.isCurrent(workID) { return }
            
            let completion = await LLMEngine.shared.generateCompletion(
                textBeforeCaret: fullActiveLine,
                liveBuffer: effectiveLiveBuffer,
                cancellationToken: generationCancellationToken,
                policy: .fullContext,
                onStream: { [weak self] partialText in
                    guard let self = self else { return }
                    guard !generationCancellationToken.isCancelled else {
                        if generationCancellationToken.shouldLogStreamSuppression() {
                            print("[Stage1B] stale/cancelled stream token suppressed requestID=\(resultRequestID)")
                        }
                        LatencyInstrumentation.shared.cancelled(requestID: resultRequestID, workID: workID, abortedByStage1B: true)
                        return
                    }
                    guard self.isGenerationResultCurrent(requestID: resultRequestID, workID: workID) else { return }
                    if atomicGhostStreamBuffer.isFullyUpgraded() {
                        return
                    }

                    let accumulatedRawOutput = atomicGhostStreamBuffer.observe(partialRawOutput: partialText, requestID: resultRequestID)
                    let result = self.atomicGhostCandidate(
                        rawOutput: accumulatedRawOutput,
                        activeLine: generationStartText,
                        requestID: resultRequestID,
                        streamBuffer: atomicGhostStreamBuffer,
                        phase: "earlyCandidate"
                    )
                    guard let candidate = result.candidate else { return }

                    if candidate.mode == "midWord" || self.atomicGhostContainsCompleteWordBoundary(candidate.suggestion) {
                        self.tryApplyAtomicGhostCandidate(
                            candidate,
                            requestSnapshot: requestSnapshot,
                            streamBuffer: atomicGhostStreamBuffer,
                            cancellationToken: generationCancellationToken,
                            source: "early",
                            recordShown: true
                        )
                    } else {
                        atomicGhostStreamBuffer.recordStableCandidate(candidate)
                        if atomicGhostStreamBuffer.shouldScheduleStabilityWindow() {
                            DispatchQueue.global(qos: .userInteractive).asyncAfter(deadline: .now() + 0.06) { [weak self] in
                                guard let self = self else { return }
                                guard self.isGenerationResultCurrent(requestID: resultRequestID, workID: workID) else { return }
                                guard let stableCandidate = atomicGhostStreamBuffer.latestCandidateForStabilityWindow() else { return }
                                self.tryApplyAtomicGhostCandidate(
                                    stableCandidate,
                                    requestSnapshot: requestSnapshot,
                                    streamBuffer: atomicGhostStreamBuffer,
                                    cancellationToken: generationCancellationToken,
                                    source: "early-stable",
                                    recordShown: true
                                )
                            }
                        }
                    }
                }
            )
            if generationCancellationToken.isCancelled {
                if atomicGhostStreamBuffer.isVisibleReserved() {
                    atomicGhostStreamBuffer.logSuppressedAfterVisible(requestID: resultRequestID)
                    return
                }
                if generationCancellationToken.shouldLogCancellationExit() {
                    print("[Stage1B] generation exited cancelled requestID=\(resultRequestID)")
                }
                LatencyInstrumentation.shared.cancelled(requestID: resultRequestID, workID: workID, abortedByStage1B: true)
                return
            }
            if atomicGhostStreamBuffer.isFullyUpgraded() {
                return
            }
            let finalRawOutput = atomicGhostStreamBuffer.finalRawOutput(engineOutput: completion)
            print("[TypeFlow-Debug] Raw model output: '\(finalRawOutput.prefix(40))'")
            if Task.isCancelled || !self.isGenerationResultCurrent(requestID: resultRequestID, workID: workID) {
                if !self.isGenerationResultCurrent(requestID: resultRequestID, workID: workID) {
                    self.recordStaleCompletedGenerationDiscard(requestID: resultRequestID, workID: workID)
                }
                print("[TypeFlow-Debug] Task was cancelled or stale work ID, ignoring output.")
                return 
	            }

	            if requestSnapshot.shouldLogFinalNoAX() {
	                print("[AXHotPath] final validation noAX requestID=\(resultRequestID)")
	                self.logAXHotPathCounts()
	            }

            let finalResult = self.atomicGhostCandidate(
                rawOutput: finalRawOutput,
                activeLine: generationStartText,
                requestID: resultRequestID,
                streamBuffer: atomicGhostStreamBuffer,
                phase: "finalCandidate"
            )
            finalResult.contract.log()
            print("[QualityAudit] finalUpdate requestID=\(resultRequestID) processed='\(self.qualityAuditPreview(finalResult.contract.suggestion))' decision=\(finalResult.contract.decision.rawValue) reason=\(finalResult.contract.reason)")

            guard let finalCandidate = finalResult.candidate else {
                self.logQualityAudit(
                    requestSnapshot: requestSnapshot,
                    rawOutput: finalRawOutput,
                    processedOutput: finalResult.contract.suggestion,
                    finalSuggestion: "",
                    phase: "final-rejected",
                    force: true
                )
                return
            }

            print("[TypeFlow-Debug] Processed completion: '\(finalCandidate.suggestion.prefix(40))'")
            self.logQualityAudit(
                requestSnapshot: requestSnapshot,
                rawOutput: finalRawOutput,
                processedOutput: finalResult.contract.suggestion,
                finalSuggestion: finalCandidate.suggestion,
                phase: "final",
                force: finalCandidate.suggestion.isEmpty
            )
            self.tryApplyAtomicGhostCandidate(
                finalCandidate,
                requestSnapshot: requestSnapshot,
                streamBuffer: atomicGhostStreamBuffer,
                cancellationToken: generationCancellationToken,
                source: "final",
                recordShown: !finalCandidate.suggestion.isEmpty
            )
	        }
	    }
    
    /// Rewrite modes for the three popover buttons.
    enum RewriteMode {
        case selectMode        // wait for user to choose tone
        case currentTone       // uses the app's active tone profile
        case professional      // formal, polished
        case shorter           // cut to the point
        case fixGrammar        // grammar + spelling only, preserve meaning
    }

    func triggerRewrite(mode: RewriteMode = .selectMode) {
        print("[TypeFlow-Debug] CompletionManager: triggerRewrite called (mode: \(mode))")

        // Cancel previous tasks/timers immediately
        workController.cancelAll()
        rewriteTask?.cancel()
        activeSpellCorrection = nil
        activeSnippetKey = nil

        if mode == .selectMode {
            // Start of rewrite session: track original PID and clear previous text
            self.activeRewritePID = self.accessibilityMonitor?.activeFocusPID
            self.activeRewriteApp = NSWorkspace.shared.frontmostApplication
            self.activeRewriteText = nil
            self.pendingCandidate = nil
            self.pendingCandidatePrefix = ""
            self.displayedCompletion = nil
            self.displayedCompletionPrefix = ""
            
            // Show the loading/mode selection overlay anchored to the selection
            DispatchQueue.main.async {
                if let rect = self.accessibilityMonitor?.getSelectionRect() {
                    self.overlayWindowController?.moveOverlay(to: rect)
                }
                self.overlayWindowController?.updateText("", isRewrite: true, isLoading: true)
            }

            // Asynchronously extract selection immediately while the target app is still frontmost
            self.rewriteTask?.cancel()
            self.rewriteTask = Task {
                try? await Task.sleep(nanoseconds: 100_000_000) // Settle delay
                
                guard let monitor = self.accessibilityMonitor,
                      let selection = await monitor.getSelectedTextWithClipboardFallback(),
                      !selection.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    print("[TypeFlow-Debug] triggerRewrite: No selection extracted, closing popover")
                    DispatchQueue.main.async { self.clearCompletion() }
                    return
                }
                
                print("[TypeFlow-Debug] triggerRewrite: Extracted selection '\(selection.prefix(30))...'")
                self.activeRewriteText = selection
            }
            return
        }

        // If a specific rewrite mode is selected:
        // 1. Immediately reactivate the target application to restore focus and selection
        if let pid = activeRewritePID, let app = NSRunningApplication(processIdentifier: pid) {
            if #available(macOS 14.0, *) {
                NSApplication.shared.yieldActivation(to: app)
                app.activate(options: [])
            } else {
                app.activate(options: [.activateIgnoringOtherApps])
            }
        }

        // 2. Update overlay to show "Generating..." spinner
        DispatchQueue.main.async {
            self.overlayWindowController?.updateText("Generating...", isRewrite: true, isLoading: true)
        }

        let bundleId = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "unknown"
        
        if mode == .selectMode {
            return // unreachable
        }

        self.rewriteTask?.cancel()
        self.rewriteTask = Task { [weak self] in
            guard let self = self else { return }
            // Ensure selection is ready (wait up to 1 second if extraction is still running)
            var attempts = 0
            while self.activeRewriteText == nil && attempts < 10 {
                try? await Task.sleep(nanoseconds: 100_000_000)
                attempts += 1
            }

            guard let selection = self.activeRewriteText,
                  !selection.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                print("[TypeFlow-Debug] triggerRewrite: Selection not available for rewrite")
                DispatchQueue.main.async { self.clearCompletion() }
                return
            }

            print("[TypeFlow-Debug] Rewriting selection")
            let rewritten = await LLMEngine.shared.generateRewrite(selectedText: selection)

            if Task.isCancelled {
                print("[TypeFlow-Debug] Rewrite generation cancelled")
                return
            }

            DispatchQueue.main.async {
                if !rewritten.isEmpty {
                    self.pendingCandidate = rewritten
                    self.pendingCandidatePrefix = ""
                    // Re-anchor overlay in case selection rect changed
                    if let rect = self.accessibilityMonitor?.getSelectionRect() {
                        self.overlayWindowController?.moveOverlay(to: rect)
                    }
                    self.overlayWindowController?.updateText(rewritten, isRewrite: true, isLoading: false)
                } else {
                    self.clearCompletion()
                }
            }
        }
    }

    func triggerSmartReply() {
        print("[TypeFlow-Debug] CompletionManager: triggerSmartReply called")
        
        workController.cancelAll()
        activeSpellCorrection = nil
        activeSnippetKey = nil
        
        self.activeSmartReplyPID = self.accessibilityMonitor?.activeFocusPID
        self.pendingCandidate = nil
        self.pendingCandidatePrefix = ""
        self.displayedCompletion = nil
        self.displayedCompletionPrefix = ""
        
        DispatchQueue.main.async {
            if let rect = self.accessibilityMonitor?.getCurrentCaretRect() {
                self.overlayWindowController?.moveOverlay(to: rect)
            }
            self.overlayWindowController?.updateText("", isLoading: true, isSmartReply: true)
        }
        
        let workID = workController.currentWorkID
        workController.replaceGenerationWork(for: workID) { [weak self] in
            guard let self = self else { return }
            try? await Task.sleep(nanoseconds: 100_000_000) // Settle delay
            
            let screenContext = ScreenContextManager.shared.latestScreenText
            let activeText = self.accessibilityMonitor?.getTextBeforeCaret() ?? ""
            
            let combinedContext = """
            On-Screen Text Context:
            \(screenContext)
            
            Currently Typed Text:
            \(activeText)
            """
            
            print("[TypeFlow-Debug] triggerSmartReply: context length = \(combinedContext.count)")
            
            let replies = await LLMEngine.shared.generateSmartReplies(contextText: combinedContext)
            
            if Task.isCancelled {
                print("[TypeFlow-Debug] triggerSmartReply cancelled")
                return
            }
            
            DispatchQueue.main.async {
                if !replies.isEmpty {
                    self.overlayWindowController?.updateText("", isSmartReply: true, smartReplyOptions: replies)
                } else {
                    self.clearCompletion()
                }
            }
        }
    }
    
    func acceptSmartReply(text: String) {
        print("[TypeFlow-Debug] Accepting smart reply: '\(text)'")
        
        let targetApp = activeSmartReplyPID.flatMap { NSRunningApplication(processIdentifier: $0) }
        let textToInject = text
        
        // 1. Hide UI + clear state on main thread immediately
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.overlayWindowController?.updateText("", isSpellCorrection: false, isRewrite: false, isLoading: false, isSmartReply: false, smartReplyOptions: [])
            self.accessibilityMonitor?.clearKeystrokeBuffer()
            self.clearCompletion()
        }
        
        // 2. Run pasteboard injection on a background thread so Thread.sleep
        //    doesn't block the main thread or prevent the UI from disappearing first.
        Task.detached(priority: .userInitiated) {
            TextInjector.shared.inject(text: textToInject, targetApp: targetApp)
        }
    }
    
    struct RenderCommit {
        let committed: Bool
        let displayedText: String
        let overlayVisible: Bool
        let requestID: UInt64?
    }
    
    func notifyRenderCommit(_ commit: RenderCommit) {
        guard commit.committed, commit.overlayVisible else {
            print("[InvisibleGhostGuard] renderCommitFailed reason=not-committed-or-invisible text='\(commit.displayedText)'")
            return
        }
        
        let isStandardCompletion = !isRewrite && activeSpellCorrection == nil && activeSnippetKey == nil
        
        if commit.displayedText == pendingCandidate {
            displayedCompletion = commit.displayedText
            displayedCompletionPrefix = pendingCandidatePrefix
            lastBufferSnapshot = accessibilityMonitor?.keystrokeBuffer ?? ""
            accessibilityMonitor?.setAcceptTapNeededForVisibleCompletion(true, reason: "render-commit")
        } else if !isStandardCompletion {
            displayedCompletion = commit.displayedText
            displayedCompletionPrefix = pendingCandidatePrefix
            lastBufferSnapshot = accessibilityMonitor?.keystrokeBuffer ?? ""
            accessibilityMonitor?.setAcceptTapNeededForVisibleCompletion(true, reason: "render-commit-special")
        } else {
             print("[InvisibleGhostGuard] renderCommitFailed reason=text-mismatch pending='\(pendingCandidate ?? "")' rendered='\(commit.displayedText)'")
        }
    }
    
    struct EditorTextSnapshot {
        let fullText: String?
        let textBeforeCaret: String
        let textAfterCaret: String
        let selectedRange: CFRange?
    }

    private func getEditorTextSnapshot() -> EditorTextSnapshot {
        guard let axElement = getFreshFocusedElement() else {
            let before = accessibilityMonitor?.getTextBeforeCaret() ?? ""
            return EditorTextSnapshot(fullText: nil, textBeforeCaret: before, textAfterCaret: "", selectedRange: nil)
        }
        
        var valueRef: CFTypeRef?
        var fullText: String? = nil
        if AXUIElementCopyAttributeValue(axElement, kAXValueAttribute as CFString, &valueRef) == .success,
           let val = valueRef {
            if let stringValue = val as? String {
                fullText = stringValue
            } else if CFGetTypeID(val) == CFAttributedStringGetTypeID() {
                let attrStr = val as! CFAttributedString
                fullText = CFAttributedStringGetString(attrStr) as String
            }
        }
        
        var rangeRef: CFTypeRef?
        var selectedRange: CFRange? = nil
        if AXUIElementCopyAttributeValue(axElement, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success,
           let rangeVal = rangeRef {
            var range = CFRange(location: 0, length: 0)
            if AXValueGetValue(rangeVal as! AXValue, .cfRange, &range) {
                selectedRange = range
            }
        }
        
        let textBefore = accessibilityMonitor?.getTextBeforeCaret() ?? ""
        
        if let fullText = fullText, let range = selectedRange {
            let utf16 = fullText.utf16
            let cursorIndex = range.location
            let safeCursorIndex = max(0, min(cursorIndex, utf16.count))
            if let sliceCaret = utf16.index(utf16.startIndex, offsetBy: safeCursorIndex, limitedBy: utf16.endIndex) {
                let before = String(fullText[..<sliceCaret])
                let after = String(fullText[sliceCaret...])
                return EditorTextSnapshot(fullText: fullText, textBeforeCaret: before, textAfterCaret: after, selectedRange: range)
            }
        }
        
        return EditorTextSnapshot(fullText: nil, textBeforeCaret: textBefore, textAfterCaret: "", selectedRange: selectedRange)
    }

    func handleTabPressed() -> Bool {
        let isVisible = overlayWindowController?.overlayWindow.isVisible ?? false
        let hasDisplayedCompletion = displayedCompletion != nil && !displayedCompletion!.isEmpty
        
        if hasDisplayedCompletion && !isVisible {
            print("[InvisibleGhostGuard] tabRejected reason=overlayHiddenWhileDisplayedCompletionExists text='\(displayedCompletion!)'")
            displayedCompletion = nil
            accessibilityMonitor?.setAcceptTapNeededForVisibleCompletion(false, reason: "invisible-guard-tab")
            return false
        }
        
        if isRewrite {
            if let completion = displayedCompletion, !completion.isEmpty {
                print("[TypeFlow-Debug] Accepting rewrite: replacing selection with '\(completion)'")
                
                let targetApp = activeRewriteApp
                
                // 1. Hide the overlay first so host app regains focus
                overlayWindowController?.updateText("", isSpellCorrection: false, isRewrite: false, isLoading: false, isSmartReply: false, smartReplyOptions: [])
                
                // 2. Clear keystroke buffer
                accessibilityMonitor?.clearKeystrokeBuffer()
                
                // 3. Forcibly reactivate target app
                targetApp?.activate(options: .activateIgnoringOtherApps)
                
                // 4. Delay and inject text asynchronously
                let completionToInject = completion
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    TextInjector.shared.inject(text: completionToInject, targetApp: targetApp)
                }
                
                // 5. Clear completion state
                clearCompletion()
            } else {
                print("[TypeFlow-Debug] Tab pressed during rewrite but completion not ready, ignoring.")
            }
            return true
        }
        
        if let spellCorrection = activeSpellCorrection {
            let activeLine = accessibilityMonitor?.getTextBeforeCaret() ?? ""
            let deleteCount = calculateDeleteCount(activeLine: activeLine, misspelled: spellCorrection.misspelled)
            print("[TypeFlow-Debug] Accept spell correction: activeLine='\(activeLine)', misspelled='\(spellCorrection.misspelled)', dynamically calculated deleteCount=\(deleteCount)")
            print("[TypeFlow-Debug] Accept spell correction: injecting \(deleteCount) backspaces and typing '\(spellCorrection.corrected)'")
            UsageStatsManager.shared.recordSpellCorrection()
            DispatchQueue.global().async {
                TextInjector.shared.injectBackspaces(count: deleteCount)
                TextInjector.shared.injectCharByChar(text: spellCorrection.corrected)
            }
            clearCompletion()
            
            let correctedLine = String(activeLine.dropLast(deleteCount)) + spellCorrection.corrected
            print("[TypeFlow-Debug] Logging Tab-accepted spelling correction to history: '\(correctedLine)'")
            TypingHistoryManager.shared.logSentenceFromText(correctedLine)
            
            return true
        }
        
        if let snippetKey = activeSnippetKey, let rawCompletion = displayedCompletion {
            let activeLine = accessibilityMonitor?.getTextBeforeCaret() ?? ""
            let resolved = resolveSnippetPlaceholders(rawCompletion)
            let (finalText, cursorOffset) = processCursorPlaceholder(resolved)
            
            TypingHistoryManager.shared.logSentence(activeLine + finalText)
            
            // Delete the shortcode
            let deleteCount = snippetKey.count
            UsageStatsManager.shared.recordSnippetFired()
            TextInjector.shared.injectBackspaces(count: deleteCount)
            
            // Inject replacement text and handle caret offset
            TextInjector.shared.inject(text: finalText, moveCursorBackCount: cursorOffset)
            
            clearCompletion()
            return true
        }

        if let completion = displayedCompletion, !completion.isEmpty {
            let startTime = CFAbsoluteTimeGetCurrent()
            
            // --- Pre-insertion snapshot ---
            let snapBefore = getEditorTextSnapshot()
            let activeLine = snapBefore.textBeforeCaret
            let activeElement = getFreshFocusedElement()
            
            // Read selected range before insertion (for diagnostics and safety)
            var selectedRangeLocationBefore = -1
            var selectedRangeLengthBefore = -1
            if let range = snapBefore.selectedRange {
                selectedRangeLocationBefore = range.location
                selectedRangeLengthBefore = range.length
            }
            
            // Compute focused PID for diagnostics
            var focusedPID: pid_t = 0
            if let elem = activeElement { AXUIElementGetPid(elem, &focusedPID) }
            let isBrowser = TextInjector.isBrowserProcess(pid: focusedPID)
            
            // Extract the next word/chunk (compute once, never repeat)
            let (acceptedChunk, remainder) = CompletionManager.getNextChunk(from: completion)
            guard !acceptedChunk.isEmpty else { return false }
            
            let expectedLineAfter = activeLine + acceptedChunk
            
            // --- Inject ---
            UsageStatsManager.shared.recordCompletionAccepted(charactersSaved: acceptedChunk.count)
            let resultDict = TextInjector.shared.injectAcceptance(
                text: acceptedChunk,
                activeElement: activeElement,
                startTime: startTime
            )
            let insertionMethod = resultDict["insertionMethod"] as? String ?? "unknown"
            let insertionAPIReportedSuccess = resultDict["insertionAPIReportedSuccess"] as? Bool ?? false
            
            // --- Post-insertion: poll for text to settle ---
            var snapAfter = getEditorTextSnapshot()
            var transformVerified = false
            
            if let fullBefore = snapBefore.fullText, let fullAfter = snapAfter.fullText {
                let expectedFullText = snapBefore.textBeforeCaret + acceptedChunk + snapBefore.textAfterCaret
                transformVerified = (fullAfter == expectedFullText)
            } else {
                let expectedLineAfter = snapBefore.textBeforeCaret + acceptedChunk
                transformVerified = (snapAfter.textBeforeCaret == expectedLineAfter)
            }
            
            if !transformVerified {
                for _ in 0..<30 {
                    RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
                    snapAfter = getEditorTextSnapshot()
                    if let fullBefore = snapBefore.fullText, let fullAfter = snapAfter.fullText {
                        let expectedFullText = snapBefore.textBeforeCaret + acceptedChunk + snapBefore.textAfterCaret
                        transformVerified = (fullAfter == expectedFullText)
                    } else {
                        let expectedLineAfter = snapBefore.textBeforeCaret + acceptedChunk
                        transformVerified = (snapAfter.textBeforeCaret == expectedLineAfter)
                    }
                    if transformVerified { break }
                }
            }
            
            // --- Transform verification ---
            let updatedLine = snapAfter.textBeforeCaret
            let replacedExistingText = !updatedLine.hasPrefix(activeLine)
            let unrelatedTextChanged = replacedExistingText
            let duplicatedAcceptedChunk = updatedLine.hasSuffix(acceptedChunk + acceptedChunk)
            
            // Count deleted lines
            var deletedLineCount = 0
            if let fullBefore = snapBefore.fullText, let fullAfter = snapAfter.fullText {
                let linesBefore = fullBefore.components(separatedBy: .newlines).count
                let linesAfter = fullAfter.components(separatedBy: .newlines).count
                deletedLineCount = max(0, linesBefore - linesAfter)
            } else {
                let linesBefore = snapBefore.textBeforeCaret.components(separatedBy: .newlines).count
                let linesAfter = snapAfter.textBeforeCaret.components(separatedBy: .newlines).count
                deletedLineCount = max(0, linesBefore - linesAfter)
            }
            
            // Native Tab Leaked check
            let tabsBefore = snapBefore.textBeforeCaret.filter { $0 == "\t" }.count
            let tabsAfter = snapAfter.textBeforeCaret.filter { $0 == "\t" }.count
            let nativeTabLeaked = tabsAfter > tabsBefore
            
            var acceptSuccess = transformVerified && !replacedExistingText && !duplicatedAcceptedChunk && deletedLineCount == 0 && !nativeTabLeaked
            var failReason = "none"
            var rollbackAttempted = false
            var rollbackSucceeded = false
            
            if !acceptSuccess {
                if replacedExistingText {
                    failReason = "destructiveInsertTransform"
                } else if duplicatedAcceptedChunk {
                    failReason = "duplicatedChunk"
                } else if deletedLineCount > 0 {
                    failReason = "linesDeleted"
                } else if nativeTabLeaked {
                    failReason = "nativeTabLeaked"
                } else if !transformVerified {
                    failReason = "transformNotVerified"
                }
                
                // Attempt Cmd+Z rollback to restore text before giving up
                if replacedExistingText || duplicatedAcceptedChunk || deletedLineCount > 0 || nativeTabLeaked {
                    rollbackAttempted = true
                    print("[TypeFlow-Debug] Destructive insertion detected — attempting Cmd+Z rollback. failReason=\(failReason)")
                    if let source = CGEventSource(stateID: .combinedSessionState),
                       let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 6, keyDown: true),  // Z = keyCode 6
                       let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 6, keyDown: false) {
                        keyDown.flags = .maskCommand
                        keyUp.flags = .maskCommand
                        keyDown.setIntegerValueField(.eventSourceUserData, value: 9999)
                        keyUp.setIntegerValueField(.eventSourceUserData, value: 9999)
                        TextInjector.shared.isInjecting = true
                        keyDown.post(tap: .cgSessionEventTap)
                        keyUp.post(tap: .cgSessionEventTap)
                        TextInjector.shared.isInjecting = false
                        // Wait for undo to land
                        for _ in 0..<15 {
                            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
                            let restored = accessibilityMonitor?.getTextBeforeCaret() ?? ""
                            if restored == activeLine {
                                rollbackSucceeded = true
                                break
                            }
                        }
                    }
                    print("[TypeFlow-Debug] Rollback result: rollbackSucceeded=\(rollbackSucceeded)")
                }
            }
            
            // --- Commit ghost state ONLY on verified success ---
            if acceptSuccess {
                if remainder.isEmpty {
                    clearCompletion(hideUI: true, reason: "tabAcceptFullyConsumed")
                } else {
                    displayedCompletion = remainder
                    displayedCompletionPrefix = displayedCompletionPrefix + acceptedChunk
                    pendingCandidate = remainder
                    pendingCandidatePrefix = displayedCompletionPrefix
                    accessibilityMonitor?.setAcceptTapNeededForVisibleCompletion(true, reason: "tabAcceptRemainder")
                    overlayWindowController?.replaceGhostTextAfterAcceptance(inserted: acceptedChunk, remainder: remainder, source: "tabAccept")
                }
            } else {
                // Insertion failed or was destructive — ghost state unchanged
                print("[TypeFlow-Debug] Accept failed: failReason=\(failReason), ghost state preserved as-is")
            }
            
            // --- Full diagnostics ---
            let diagnostic: [String: Any] = [
                "epochSeconds": Date().timeIntervalSince1970,
                "tabAcceptMode": "wordChunk",
                "displayedCompletionBefore": completion,
                "acceptedChunk": acceptedChunk,
                "displayedCompletionAfter": acceptSuccess ? remainder : completion,
                "lineBefore": activeLine,
                "lineAfter": updatedLine,
                "expectedLineAfter": expectedLineAfter,
                "selectedRangeLocationBefore": selectedRangeLocationBefore,
                "selectedRangeLengthBefore": selectedRangeLengthBefore,
                "selectedRangeLocationAfter": snapAfter.selectedRange?.location ?? -1,
                "selectedRangeLengthAfter": snapAfter.selectedRange?.length ?? -1,
                "insertionMethod": insertionMethod,
                "insertionAPIReportedSuccess": insertionAPIReportedSuccess,
                "isBrowser": isBrowser,
                "transformVerified": transformVerified,
                "fullTransformVerified": transformVerified,
                "acceptSuccess": acceptSuccess,
                "replacedExistingText": replacedExistingText,
                "unrelatedTextChanged": unrelatedTextChanged,
                "duplicatedAcceptedChunk": duplicatedAcceptedChunk,
                "deletedLineCount": deletedLineCount,
                "nativeTabLeaked": nativeTabLeaked,
                "rollbackAttempted": rollbackAttempted,
                "rollbackSucceeded": rollbackSucceeded,
                "failReason": failReason,
                // Legacy keys for benchmark scorer
                "insertedAtomically": resultDict["insertedAtomically"] ?? false,
                "perCharacterFallback": resultDict["perCharacterFallback"] ?? false,
                "acceptToFullInsertedMs": resultDict["acceptToFullInsertedMs"] ?? 0.0,
                "unrelatedTextChanged_legacy": unrelatedTextChanged,
                "insertedAtCaretVerified": transformVerified,
                "insertionSucceeded": acceptSuccess,
                "fallbackPathUsed": false,
                "duplicatedAcceptedChunk_legacy": duplicatedAcceptedChunk,
                "replacedExistingText_legacy": replacedExistingText,
                "finalEditorTextSuffix": String(updatedLine.suffix(30))
            ]
            
            if let dictData = try? JSONSerialization.data(withJSONObject: diagnostic),
               let jsonStr = String(data: dictData, encoding: .utf8) {
                print("[AcceptDiagnostic] \(jsonStr)")
                fflush(stdout)
            }
            
            return true // We handled the Tab key
        }
        return false // Let the event pass through
    }
    
    static func getNextChunk(from completion: String) -> (chunk: String, remainder: String) {
        if completion.isEmpty {
            return ("", "")
        }
        
        let chars = Array(completion)
        var idx = 0
        
        // 1. Consume any leading whitespace
        while idx < chars.count && chars[idx].isWhitespace {
            idx += 1
        }
        
        // 2. Consume word characters or punctuation
        if idx < chars.count {
            let isPunct = chars[idx].isPunctuation
            if isPunct {
                // If starting with punctuation, consume all consecutive punctuation
                while idx < chars.count && chars[idx].isPunctuation {
                    idx += 1
                }
            } else {
                // Consume normal word characters (alphanumeric) plus any attached punctuation at the end (like comma, period)
                while idx < chars.count && !chars[idx].isWhitespace && !chars[idx].isPunctuation {
                    idx += 1
                }
                // Consume trailing punctuation attached to the word (e.g., "word," or "word.") but not bracket/parenthesis boundaries
                while idx < chars.count && chars[idx].isPunctuation && chars[idx] != "(" && chars[idx] != "{" && chars[idx] != "[" {
                    idx += 1
                }
            }
        }
        
        // 3. Consume one trailing space if present
        if idx < chars.count && chars[idx] == " " {
            idx += 1
        }
        
        let chunk = String(chars[..<idx])
        let remainder = String(chars[idx...])
        return (chunk, remainder)
    }
    
    private func getFreshFocusedElement() -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedRef: AnyObject?
        let err = AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedRef)
        if err == .success, let element = focusedRef {
            return (element as! AXUIElement)
        }
        return nil
    }
    
    func cancelInflightTasks() {
        requestActiveGenerationAbort(reason: "cancel-inflight")
        workController.cancelAll()
        debounceAuditReset(reason: "cancel-inflight")
        rewriteTask?.cancel()
    }
    
    func hideOverlay() {
        overlayWindowController?.updateText("", isSpellCorrection: false, isRewrite: false, isLoading: false, isSmartReply: false, smartReplyOptions: [])
    }

    func clearCompletion(hideUI: Bool = true, reason: String = "unspecified") {
        let hadCompletion = displayedCompletion?.isEmpty == false || pendingCandidate?.isEmpty == false
        if hadCompletion {
            print("[GhostVisibility] cleared reason=\(reason) hadDisplayed=\(displayedCompletion?.isEmpty == false) hadPending=\(pendingCandidate?.isEmpty == false)")
        }
        accessibilityMonitor?.setAcceptTapNeededForVisibleCompletion(false, reason: "clearCompletion:\(reason)")
        pendingCandidate = nil
        pendingCandidatePrefix = ""
        displayedCompletion = nil
        displayedCompletionPrefix = ""
        activeSpellCorrection = nil
        activeSnippetKey = nil
        activeRewriteText = nil
        activeRewritePID = nil
        activeRewriteApp = nil
        activeSmartReplyPID = nil
        lastBufferSnapshot = ""
        cancelInflightTasks()
        if hideUI {
            hideOverlay()
        }
    }

    func handleReturnPressed() {
        // Wait slightly for the target app to process the Return key before polling AX API
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self = self else { return }
            let textAfterReturn = self.accessibilityMonitor?.getTextBeforeCaret()
            
            if textAfterReturn == nil || textAfterReturn!.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                print("[TypeFlow-Debug] Smart Submission Detected: Field is empty or lost focus after Return.")
                self.isSuppressedUntilNextTyping = true
                self.workController.cancelAll()
                self.overlayWindowController?.updateText("")
                self.clearCompletion()
            } else {
                print("[TypeFlow-Debug] Multi-line Newline Detected. Not suppressing.")
            }
        }
    }
    
    private func hasWordBoundaryBeforeSuffix(activeLine: String, suffix: String) -> Bool {
        guard activeLine.hasSuffix(suffix) else { return false }
        let prefixLength = activeLine.count - suffix.count
        guard prefixLength > 0 else { return true } // Start of line is a boundary
        
        let index = activeLine.index(activeLine.startIndex, offsetBy: prefixLength - 1)
        let charBefore = activeLine[index]
        return charBefore.isWhitespace || charBefore.isPunctuation
    }
    
    private func resolveSnippetPlaceholders(_ template: String) -> String {
        var result = template
        
        // 1. Resolve {{date}}
        if result.contains("{{date}}") {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            let dateString = formatter.string(from: Date())
            result = result.replacingOccurrences(of: "{{date}}", with: dateString)
        }
        
        // 2. Resolve {{time}}
        if result.contains("{{time}}") {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            let timeString = formatter.string(from: Date())
            result = result.replacingOccurrences(of: "{{time}}", with: timeString)
        }
        
        // 3. Resolve {{clipboard}}
        if result.contains("{{clipboard}}") {
            let clipboardString = NSPasteboard.general.string(forType: .string) ?? ""
            result = result.replacingOccurrences(of: "{{clipboard}}", with: clipboardString)
        }
        
        return result
    }
    
    private func processCursorPlaceholder(_ text: String) -> (finalText: String, cursorOffset: Int) {
        guard let range = text.range(of: "{{cursor}}") else {
            return (text, 0)
        }
        
        let finalText = text.replacingOccurrences(of: "{{cursor}}", with: "")
        let substringAfterCursor = text[range.upperBound...]
        let cleanSubstring = substringAfterCursor.replacingOccurrences(of: "{{cursor}}", with: "")
        let cursorOffset = cleanSubstring.count
        
        return (finalText, cursorOffset)
    }
    
    func stripMarkdown(_ text: String) -> String {
        var result = text
        
        // Only strip trailing backticks the model might append
        if result.hasSuffix("```") {
            result = String(result.dropLast(3))
        } else if result.hasSuffix("``") {
            result = String(result.dropLast(2))
        } else if result.hasSuffix("`") {
            result = String(result.dropLast(1))
        }
        
        return result
    }
}

final class SuggestionWorkController: @unchecked Sendable {
    private var debounceTask: Task<Void, Never>?
    private var generationTask: Task<Void, Never>?
    private var isGenTaskActive = false
    private var latestWorkID: UInt64 = 0
    private var latestGenWorkID: UInt64 = 0
    private let lock = NSLock()

    var currentWorkID: UInt64 {
        lock.lock()
        defer { lock.unlock() }
        return latestWorkID
    }

    var isGenerationRunning: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isGenTaskActive
    }

    func setGenerationFinished() {
        lock.lock()
        isGenTaskActive = false
        generationTask = nil
        lock.unlock()
    }

    @discardableResult
    func replaceDebouncedWork(
        delayMilliseconds: Int,
        operation: @escaping @Sendable (UInt64) async -> Void
    ) -> UInt64 {
        lock.lock()
        debounceTask?.cancel()
        latestWorkID &+= 1
        let workID = latestWorkID
        lock.unlock()

        let task = Task {
            defer {
                lock.lock()
                if self.latestWorkID == workID {
                    self.debounceTask = nil
                }
                lock.unlock()
            }
            let delayNanoseconds = UInt64(delayMilliseconds) * 1_000_000
            try? await Task.sleep(nanoseconds: delayNanoseconds)
            if Task.isCancelled || !isCurrent(workID) { return }
            await operation(workID)
        }
        
        lock.lock()
        debounceTask = task
        lock.unlock()
        return workID
    }

    func replaceGenerationWork(
        for workID: UInt64,
        operation: @escaping @Sendable () async -> Void
    ) {
        lock.lock()
        generationTask?.cancel()
        isGenTaskActive = true
        latestGenWorkID = workID
        lock.unlock()

        let task = Task {
            defer {
                lock.lock()
                self.isGenTaskActive = false
                if self.latestGenWorkID == workID {
                    self.generationTask = nil
                }
                lock.unlock()
            }
            if Task.isCancelled || !isCurrent(workID) { return }
            await operation()
        }
        
        lock.lock()
        generationTask = task
        lock.unlock()
    }

    func cancelAll() {
        lock.lock()
        debounceTask?.cancel()
        generationTask?.cancel()
        debounceTask = nil
        generationTask = nil
        isGenTaskActive = false
        latestWorkID &+= 1
        latestGenWorkID &+= 1
        lock.unlock()
    }

    func isCurrent(_ workID: UInt64) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return workID == latestWorkID
    }
}

struct SuggestionInteractionState {
    enum ContinuationDecision: String {
        case accepted
        case rejected
        case truncated
    }

    struct ContinuationContract {
        let suggestion: String
        let decision: ContinuationDecision
        let reason: String
        let mode: String
        let rawCompletion: String
        let activeLine: String
        let partialWord: String
        let preservedLeadingWhitespace: Bool
        let removedDuplicatePrefix: String

        var isRenderable: Bool {
            return (decision == .accepted || decision == .truncated) && !suggestion.isEmpty
        }

        func log() {
            print("[QualityContract] raw='\(Self.preview(rawCompletion))' activeLine='\(Self.preview(activeLine))' partialWord='\(Self.preview(partialWord))' mode=\(mode)")
            print("[QualityContract] decision=\(decision.rawValue) reason=\(reason)")
            print("[QualityContract] preservedLeadingWhitespace=\(preservedLeadingWhitespace)")
            print("[QualityContract] removedDuplicatePrefix='\(Self.preview(removedDuplicatePrefix))'")
            if reason == "pureOverlap" {
                print("[QualityContract] rejectedPureOverlap")
            }
            if reason == "punctuationOnly" || reason == "whitespaceOnly" {
                print("[QualityContract] rejectedPunctuationOnly")
            }
            if reason == "repeatedTokenLoop" {
                if decision == .rejected {
                    print("[QualityContract] rejectedRepeatedTokenLoop")
                } else if decision == .truncated {
                    print("[QualityContract] truncatedRepeatedTokenLoop")
                }
            }
            if reason == "invalidMidWordContinuation" {
                print("[QualityContract] rejectedInvalidMidWordContinuation")
            }
            print("[QualityContract] finalSuggestion='\(Self.preview(suggestion))'")
        }

        static func preview(_ text: String, limit: Int = 220) -> String {
            let escaped = text
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\n", with: "\\n")
                .replacingOccurrences(of: "\t", with: "\\t")
                .replacingOccurrences(of: "'", with: "\\'")
            if escaped.count <= limit { return escaped }
            return "..." + String(escaped.suffix(limit))
        }
    }

    static func canonicalizeContinuation(activeLine: String, rawCompletion: String) -> ContinuationContract {
        let partialWord = currentPartialWord(in: activeLine)
        let mode: String
        if activeLine.last?.isWhitespace == true {
            mode = "afterSpace"
        } else if partialWord.isEmpty {
            mode = "midWord"
        } else {
            mode = "partialWord"
        }

        guard !rawCompletion.isEmpty else {
            return makeContract("", .rejected, "empty", mode, rawCompletion, activeLine, partialWord, false, "")
        }

        let trimmedRaw = rawCompletion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedRaw.isEmpty else {
            return makeContract("", .rejected, "whitespaceOnly", mode, rawCompletion, activeLine, partialWord, false, "")
        }
        if isPunctuationOnly(trimmedRaw) {
            return makeContract("", .rejected, "punctuationOnly", mode, rawCompletion, activeLine, partialWord, false, "")
        }
        if isPureOverlap(activeLine: activeLine, candidate: trimmedRaw) {
            return makeContract("", .rejected, "pureOverlap", mode, rawCompletion, activeLine, partialWord, false, trimmedRaw)
        }

        var candidate = rawCompletion
        var removedDuplicatePrefix = ""
        var preservedLeadingWhitespace = candidate.first?.isWhitespace == true
        let leadingWhitespace = String(candidate.prefix { $0.isWhitespace })
        let withoutLeadingWhitespace = String(candidate.dropFirst(leadingWhitespace.count))

        let trimmedActive = activeLine.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedActive.count <= 4 {
            let lower = trimmedActive.lowercased()
            if ["the", "a", "an", "is", "in", "it", "to", "of", "and", "this", "that"].contains(lower) {
                return makeContract("", .rejected, "activeLineTooShortAndGeneric", mode, rawCompletion, activeLine, partialWord, false, "")
            }
        }

        if mode == "partialWord" {
            if rawCompletion.first?.isWhitespace == true {
                return makeContract("", .rejected, "invalidMidWordContinuation", mode, rawCompletion, activeLine, partialWord, false, "")
            }
            if let firstChar = candidate.first, firstChar.isUppercase, partialWord.last?.isLowercase == true {
                return makeContract("", .rejected, "invalidMidWordContinuation", mode, rawCompletion, activeLine, partialWord, false, "")
            }
        }

        if mode == "afterSpace" {
            if withoutLeadingWhitespace.first?.isUppercase == true {
                print("[QualityContract] suspiciousUppercaseAfterSpace raw='\(ContinuationContract.preview(rawCompletion))'")
            }
        }

        if !partialWord.isEmpty && withoutLeadingWhitespace.lowercased().hasPrefix(partialWord.lowercased()) {
            let prefixEnd = withoutLeadingWhitespace.index(withoutLeadingWhitespace.startIndex, offsetBy: partialWord.count)
            let novelSuffix = String(withoutLeadingWhitespace[prefixEnd...])
            removedDuplicatePrefix = partialWord

            if novelSuffix.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return makeContract("", .rejected, "pureOverlap", mode, rawCompletion, activeLine, partialWord, false, removedDuplicatePrefix)
            }

            candidate = novelSuffix
            preservedLeadingWhitespace = false
        } else if !partialWord.isEmpty && candidate.first?.isWhitespace == true {
            candidate = withoutLeadingWhitespace
            preservedLeadingWhitespace = false
        } else if activeLine.last?.isWhitespace == true && candidate.first?.isWhitespace == true {
            candidate = withoutLeadingWhitespace
            preservedLeadingWhitespace = false
        }

        candidate = truncateAtFirstNewline(candidate)

        let loopCheck = removeRepeatedTokenLoop(from: candidate)
        var finalDecision: ContinuationDecision = .accepted
        var finalReason = "validContinuation"

        if loopCheck.rejected {
            return makeContract("", .rejected, "repeatedTokenLoop", mode, rawCompletion, activeLine, partialWord, preservedLeadingWhitespace, removedDuplicatePrefix)
        }
        if loopCheck.truncated {
            candidate = loopCheck.text
            finalDecision = .truncated
            finalReason = "repeatedTokenLoop"
            if candidate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return makeContract("", .rejected, "repeatedTokenLoop", mode, rawCompletion, activeLine, partialWord, preservedLeadingWhitespace, removedDuplicatePrefix)
            }
        }

        if candidate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return makeContract("", .rejected, "empty", mode, rawCompletion, activeLine, partialWord, preservedLeadingWhitespace, removedDuplicatePrefix)
        }
        if isPunctuationOnly(candidate.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return makeContract("", .rejected, "punctuationOnly", mode, rawCompletion, activeLine, partialWord, preservedLeadingWhitespace, removedDuplicatePrefix)
        }
        if isPureOverlap(activeLine: activeLine, candidate: candidate.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return makeContract("", .rejected, "pureOverlap", mode, rawCompletion, activeLine, partialWord, preservedLeadingWhitespace, removedDuplicatePrefix)
        }

        return makeContract(candidate, finalDecision, finalReason, mode, rawCompletion, activeLine, partialWord, preservedLeadingWhitespace, removedDuplicatePrefix)
    }

    static func sliceGeneratedSuffix(activeLine: String, rawCompletion: String) -> String {
        return canonicalizeContinuation(activeLine: activeLine, rawCompletion: rawCompletion).suggestion
    }

    private static func makeContract(
        _ suggestion: String,
        _ decision: ContinuationDecision,
        _ reason: String,
        _ mode: String,
        _ rawCompletion: String,
        _ activeLine: String,
        _ partialWord: String,
        _ preservedLeadingWhitespace: Bool,
        _ removedDuplicatePrefix: String
    ) -> ContinuationContract {
        ContinuationContract(
            suggestion: suggestion,
            decision: decision,
            reason: reason,
            mode: mode,
            rawCompletion: rawCompletion,
            activeLine: activeLine,
            partialWord: partialWord,
            preservedLeadingWhitespace: preservedLeadingWhitespace,
            removedDuplicatePrefix: removedDuplicatePrefix
        )
    }

    private static func currentPartialWord(in text: String) -> String {
        let separators = CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)
        let scalars = Array(text.unicodeScalars)
        var suffixScalars: [UnicodeScalar] = []
        for scalar in scalars.reversed() {
            if separators.contains(scalar) { break }
            suffixScalars.append(scalar)
        }
        return String(String.UnicodeScalarView(suffixScalars.reversed()))
    }

    private static func isPunctuationOnly(_ text: String) -> Bool {
        let allowed = CharacterSet.punctuationCharacters
            .union(.symbols)
            .union(.whitespacesAndNewlines)
        return !text.isEmpty && text.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    private static func isPureOverlap(activeLine: String, candidate: String) -> Bool {
        let normalizedActive = activeLine.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedCandidate = candidate.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedActive.isEmpty, !normalizedCandidate.isEmpty else { return false }
        return normalizedActive.hasSuffix(normalizedCandidate)
    }

    private static func truncateAtFirstNewline(_ text: String) -> String {
        guard let newlineRange = text.rangeOfCharacter(from: .newlines) else { return text }
        return String(text[..<newlineRange.lowerBound])
    }

    private static func removeRepeatedTokenLoop(from text: String) -> (text: String, truncated: Bool, rejected: Bool) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if isCompactRepeatedToken(trimmed) {
            return ("", false, true)
        }

        let pattern = #"\b([\p{L}\p{N}_]+)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return (text, false, false)
        }
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex.matches(in: text, options: [], range: nsRange)
        guard matches.count >= 3 else { return (text, false, false) }

        var previousToken: String?
        var repeatCount = 0
        for match in matches {
            guard let tokenRange = Range(match.range(at: 1), in: text) else { continue }
            let token = String(text[tokenRange]).lowercased()
            if token == previousToken {
                repeatCount += 1
            } else {
                previousToken = token
                repeatCount = 1
            }

            if repeatCount >= 2 {
                let truncateIndex = tokenRange.lowerBound
                let truncatedString = String(text[..<truncateIndex])
                return (truncatedString, true, false)
            }
        }

        return (text, false, false)
    }

    private static func isCompactRepeatedToken(_ text: String) -> Bool {
        guard text.count >= 4,
              text.rangeOfCharacter(from: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)) == nil
        else {
            return false
        }

        let lower = text.lowercased()
        for size in 1...(lower.count / 2) {
            guard lower.count % size == 0 else { continue }
            let end = lower.index(lower.startIndex, offsetBy: size)
            let unit = String(lower[..<end])
            guard unit.count >= 2 else { continue }
            let repeated = String(repeating: unit, count: lower.count / size)
            if repeated == lower {
                return true
            }
        }
        return false
    }
}
