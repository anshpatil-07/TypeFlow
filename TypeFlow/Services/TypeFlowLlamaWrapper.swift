import Foundation
import LlamaSwift

// Global C-callback for cancellation
private func abortCallback(data: UnsafeMutableRawPointer?) -> Bool {
    guard let data = data else { return false }
    return data.assumingMemoryBound(to: Bool.self).pointee
}

actor TypeFlowLlamaWrapper {
    private var model: OpaquePointer?
    private var ctx: OpaquePointer?
    private var isLoaded = false
    private var abortInFlight = false
    
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
cparams.n_ctx = 8192      // Double the context window to give plenty of room
cparams.n_batch = 2048    // Cap the batch size
cparams.n_ubatch = 512    // Keep micro-batching standard for Apple Silicon
        
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
        print("[TypeFlow-Debug] LlamaWrapper: Model unloaded from memory.")
    }
    
    func generate(
        prompt: String,
        maxTokens: Int,
        temperature: Float,
        onPartialRawText: ((String) -> Void)? = nil
    ) throws -> String {
        guard isLoaded, let model = model, let ctx = ctx else {
            throw NSError(domain: "TypeFlowLlamaWrapper", code: 3, userInfo: [NSLocalizedDescriptionKey: "Model not loaded"])
        }
        
        let vocab = llama_model_get_vocab(model)
        
        // 1. Hardware Cancellation Binding
        abortInFlight = false
        withUnsafeMutablePointer(to: &abortInFlight) { ptr in
            llama_set_abort_callback(ctx, abortCallback, ptr)
        }
        
        // 2. Tokenize Prompt
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
        
        // 3. Initial Prompt Decode
        var batch = llama_batch_get_one(&tokens, n_tokens)
        
        if llama_decode(ctx, batch) != 0 {
            throw NSError(domain: "TypeFlowLlamaWrapper", code: 5, userInfo: [NSLocalizedDescriptionKey: "llama_decode failed on prompt prefill"])
        }
        
        var generatedText = ""
        var n_cur: Int32 = n_tokens
        
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
            if Task.isCancelled {
                print("[TypeFlow-Debug] LlamaWrapper: Task.isCancelled detected. Firing native abort flag.")
                abortInFlight = true 
                break
            }
            
            // Sample
            let new_token_id = llama_sampler_sample(smpl, ctx, -1)
            
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
                    onPartialRawText?(generatedText)
                }
            }
            
            // Push token to batch
            var tokenArr = [new_token_id]
            batch = llama_batch_get_one(&tokenArr, 1)
            
            if llama_decode(ctx, batch) != 0 {
                break
            }
            
            n_cur += 1
        }
        
        llama_sampler_free(smpl)
        return generatedText
    }
}
