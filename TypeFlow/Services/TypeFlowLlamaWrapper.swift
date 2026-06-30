import Foundation
import LlamaSwift

final class LlamaGenerationCancellationToken: @unchecked Sendable {
    let requestID: UInt64
    let workID: UInt64

    private let lock = NSLock()
    private var cancelled = false
    private var abortCallbackLogged = false

    init(requestID: UInt64, workID: UInt64) {
        self.requestID = requestID
        self.workID = workID
    }

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    @discardableResult
    func requestCancellation() -> Bool {
        lock.lock()
        let wasAlreadyCancelled = cancelled
        cancelled = true
        lock.unlock()
        return !wasAlreadyCancelled
    }

    func shouldAbortFromCallback() -> Bool {
        lock.lock()
        let shouldAbort = cancelled
        let shouldLog = shouldAbort && !abortCallbackLogged
        if shouldLog {
            abortCallbackLogged = true
        }
        lock.unlock()

        if shouldLog {
            print("[Stage1B] abort callback triggered requestID=\(requestID)")
        }

        return shouldAbort
    }
}

// Global C-callback for cancellation
private func abortCallback(data: UnsafeMutableRawPointer?) -> Bool {
    guard let data = data else { return false }
    let token = Unmanaged<LlamaGenerationCancellationToken>.fromOpaque(data).takeUnretainedValue()
    return token.shouldAbortFromCallback()
}

actor TypeFlowLlamaWrapper {
    private var model: OpaquePointer?
    private var ctx: OpaquePointer?
    private var isLoaded = false
    private var previousPromptTokens: [llama_token] = []
    private var currentCachePosition: Int32 = 0
    
    var isModelReady: Bool { isLoaded }
    
    init() {
        llama_backend_init()
    }
    
    deinit {
        unloadModel()
        llama_backend_free()
    }
    
    func loadModel(path: String) throws {
        unloadModel()
        print("[TypeFlow-Debug] LlamaWrapper: Loading model from \(path)")
        
        var mparams = llama_model_default_params()
        // Hardware Strictness: Ensure memory mapping is enabled
        mparams.use_mmap = true
        // Enable Metal GPU support if available by setting a high number of layers
        mparams.n_gpu_layers = 99
        
        model = llama_load_model_from_file(path, mparams)
        guard let model = model else {
            throw NSError(domain: "TypeFlowLlamaWrapper", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to load model from \(path)"])
        }
        
        var cparams = llama_context_default_params()
        cparams.n_ctx = 4096      // Hardcoded bounding limit to prevent KV cache overflow
        cparams.n_batch = 2048    // Ensure prefill batch capacity can handle 550+ tokens
        cparams.n_ubatch = 512    // Match physical batch size for Apple Silicon
        
        ctx = llama_new_context_with_model(model, cparams)
        guard let ctx = ctx else {
            llama_free_model(model)
            self.model = nil
            throw NSError(domain: "TypeFlowLlamaWrapper", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to create context"])
        }
        
        isLoaded = true
        print("[TypeFlow-Debug] LlamaWrapper: Model and context fully loaded.")
        
        // ── Metal Kernel Pre-compilation Warmup ──────────────────────────────────
        // llama.cpp compiles Metal compute pipelines lazily on first use, causing
        // severe latency spikes ("compiling pipeline: kernel_mul_mm_...") during
        // live typing inference. Running a single dummy decode immediately after
        // context creation forces all required Metal library shaders to compile and
        // cache up front, so every subsequent real generation call is free of that
        // overhead. The dummy decode is discarded; KV cache is cleared immediately.
        print("[TypeFlow-Debug] LlamaWrapper: Running Metal warmup pass to pre-compile GPU kernels...")

        // ── Stage 1: Batch decode (compiles kernel_mul_mm_* prefill pipelines) ──
        var dummyToken = llama_token_bos(llama_model_get_vocab(model))
        var warmupBatch = llama_batch_get_one(&dummyToken, 1)
        let warmupStatus = llama_decode(ctx, warmupBatch)
        if warmupStatus != 0 {
            print("[TypeFlow-Debug] LlamaWrapper: Metal warmup stage 1 decode failed (code \(warmupStatus)) — continuing anyway.")
        } else {
            // ── Stage 2: Single-token autoregressive decode ─────────────────────
            // The batch decode above only compiles the multi-token prefill kernels.
            // The autoregressive vector kernels (kernel_flash_attn_ext_vec_f16_*)
            // are compiled lazily on the FIRST single-token decode during active
            // generation. We force that compilation now by sampling and immediately
            // re-decoding one token at batch size = 1.
            let sparams = llama_sampler_chain_default_params()
            if let smpl = llama_sampler_chain_init(sparams) {
                llama_sampler_chain_add(smpl, llama_sampler_init_greedy())
                let sampledToken = llama_sampler_sample(smpl, ctx, -1)
                llama_sampler_free(smpl)

                var singleToken = sampledToken
                var singleBatch = llama_batch_get_one(&singleToken, 1)
                let vecStatus = llama_decode(ctx, singleBatch)
                if vecStatus != 0 {
                    print("[TypeFlow-Debug] LlamaWrapper: Metal warmup stage 2 (_vec_) decode failed (code \(vecStatus)) — continuing anyway.")
                } else {
                    print("[TypeFlow-Debug] LlamaWrapper: Metal warmup complete. Batch + vector GPU kernels pre-compiled.")
                }
            }
        }

        // Discard all warmup KV state before the first real request.
        llama_memory_clear(llama_get_memory(ctx), false)
        self.previousPromptTokens = []
        self.currentCachePosition = 0
    }
    
    func unloadModel() {
        if let ctx = ctx {
            llama_free(ctx)
            self.ctx = nil
        }
        if let model = model {
            llama_free_model(model)
            self.model = nil
        }
        isLoaded = false
        previousPromptTokens = []
        currentCachePosition = 0
        print("[TypeFlow-Debug] LlamaWrapper: Model unloaded from memory.")
    }
    
    func generate(
        prompt: String,
        maxTokens: Int,
        temperature: Float,
        cancellationToken: LlamaGenerationCancellationToken? = nil,
        onPartialRawText: (@Sendable (String) -> Void)? = nil
    ) throws -> String {
        guard isLoaded, let model = model, let ctx = ctx else {
            throw NSError(domain: "TypeFlowLlamaWrapper", code: 3, userInfo: [NSLocalizedDescriptionKey: "Model not loaded"])
        }
        
        let vocab = llama_model_get_vocab(model)
        
        if let cancellationToken {
            let tokenPointer = Unmanaged.passUnretained(cancellationToken).toOpaque()
            llama_set_abort_callback(ctx, abortCallback, tokenPointer)
        } else {
            llama_set_abort_callback(ctx, nil, nil)
        }
        defer {
            llama_set_abort_callback(ctx, nil, nil)
        }
        
        // 1.5 Tokenize Prompt & Smart Sequence Matching
        var tokens = [llama_token](repeating: 0, count: Int(llama_n_ctx(ctx)))
        var n_tokens: Int32 = 0
        let promptCount = Int32(prompt.utf8.count)
        
        let tokenizeResult = prompt.withCString { cStr in
            return llama_tokenize(vocab, cStr, promptCount, &tokens, Int32(tokens.count), true, true)
        }
        
        if tokenizeResult < 0 {
            throw NSError(domain: "TypeFlowLlamaWrapper", code: 4, userInfo: [NSLocalizedDescriptionKey: "Tokenization failed. Prompt too long?"])
        }
        n_tokens = tokenizeResult
        let newPromptTokens = Array(tokens.prefix(Int(n_tokens)))
        
        // Find how many tokens match our previously evaluated prompt state
        var matchingLength = 0
        for i in 0..<min(previousPromptTokens.count, newPromptTokens.count) {
            if previousPromptTokens[i] == newPromptTokens[i] {
                matchingLength += 1
            } else {
                break
            }
        }
        
        // Only clear tokens that changed! Do not clear everything.
        // We drop from `matchingLength` to the end, removing any trailing sequence or generated tokens
        llama_memory_seq_rm(llama_get_memory(ctx), 0, Int32(matchingLength), -1)
        
        self.previousPromptTokens = newPromptTokens
        self.currentCachePosition = Int32(matchingLength)
        
        // 3. Initial Prompt Decode (only the un-cached remainder)
        if matchingLength < newPromptTokens.count {
            if Task.isCancelled || cancellationToken?.isCancelled == true {
                throw CancellationError()
            }

            var remainderTokens = Array(newPromptTokens[matchingLength...])
            let batch = llama_batch_get_one(&remainderTokens, Int32(remainderTokens.count))
            
            if llama_decode(ctx, batch) != 0 {
                if cancellationToken?.isCancelled == true {
                    throw CancellationError()
                }
                throw NSError(domain: "TypeFlowLlamaWrapper", code: 5, userInfo: [NSLocalizedDescriptionKey: "llama_decode failed on prompt prefill"])
            }
        }
        
        var generatedText = ""
        var n_cur: Int32 = n_tokens
        var hasEmittedValidText = false
        
        // 4. Setup Sampler
        let sparams = llama_sampler_chain_default_params()
        guard let smpl = llama_sampler_chain_init(sparams) else {
            throw NSError(domain: "TypeFlowLlamaWrapper", code: 6, userInfo: [NSLocalizedDescriptionKey: "Failed to init sampler"])
        }
        llama_sampler_chain_add(smpl, llama_sampler_init_greedy())
        if temperature > 0.0 {
            llama_sampler_chain_add(smpl, llama_sampler_init_temp(temperature))
        }
        
        // 5. Generation Loop
        for _ in 0..<maxTokens {
            // Hardware Cancellation: Check Swift concurrency state
            if Task.isCancelled || cancellationToken?.isCancelled == true {
                // DO NOT call llama_kv_cache_seq_rm here! Just exit the thread execution.
                throw CancellationError()
            }
            
            // Sample
            var new_token_id = llama_sampler_sample(smpl, ctx, -1)
            
            // Prevent Premature EOS
            while llama_vocab_is_eog(vocab, new_token_id) && !hasEmittedValidText {
                if let logits = llama_get_logits_ith(ctx, -1) {
                    logits[Int(new_token_id)] = -Float.greatestFiniteMagnitude
                    new_token_id = llama_sampler_sample(smpl, ctx, -1)
                } else {
                    break
                }
            }
            
            if llama_vocab_is_eog(vocab, new_token_id) {
                break
            }
            
            // Memory Strictness: Zero-copy UnsafeMutableBufferPointer extraction
            var pieceBuffer = [CChar](repeating: 0, count: 64)
            let bytesWritten = pieceBuffer.withUnsafeMutableBufferPointer { bufPtr -> Int32 in
                return llama_token_to_piece(vocab, new_token_id, bufPtr.baseAddress, Int32(bufPtr.count), 0, false)
            }
            
            if bytesWritten > 0 {
                // Ensure null termination safely
                pieceBuffer[Int(bytesWritten)] = 0
                if let pieceString = String(validatingUTF8: pieceBuffer) {
                    generatedText += pieceString
                    
                    if !hasEmittedValidText {
                        while generatedText.hasPrefix("\n") || generatedText.hasPrefix("\r") {
                            generatedText.removeFirst()
                        }
                        if generatedText.rangeOfCharacter(from: .alphanumerics) != nil {
                            hasEmittedValidText = true
                        }
                    }
                    
                    if hasEmittedValidText && generatedText.contains("\n") {
                        if let newlineRange = generatedText.range(of: "\n") {
                            generatedText = String(generatedText[..<newlineRange.lowerBound])
                        }
                        onPartialRawText?(generatedText)
                        break
                    }
                    if cancellationToken?.isCancelled == true {
                        throw CancellationError()
                    }
                    onPartialRawText?(generatedText)
                }
            }
            
            // Explicit string-based stop sequences for base models (FIM boundary markers).
            // Do NOT scan for <end_of_turn> or <start_of_turn> — those are Gemma Instruct chat
            // template tokens and will never appear in base model output; scanning for them on
            // every token wastes CPU and causes spurious truncations if the model emits angle brackets.
            if generatedText.contains("<|endoftext|>") {
                if let stopIdx = generatedText.range(of: "<|endoftext|>")?.lowerBound {
                    generatedText = String(generatedText[..<stopIdx])
                }
                break
            }
            
            // Push token to batch
            var tokenArr = [new_token_id]
            let batch = llama_batch_get_one(&tokenArr, 1)
            
            if llama_decode(ctx, batch) != 0 {
                if cancellationToken?.isCancelled == true {
                    throw CancellationError()
                }
                break
            }
            
            // Append generated tokens to our prefix array so subsequent calls can match them if needed
            self.previousPromptTokens.append(new_token_id)
            
            n_cur += 1
        }
        
        llama_sampler_free(smpl)
        return generatedText
    }
}
