# TypeFlow Storage Audit

## Executive Summary
- **Total repository logical size:** ~150 GB (due to sparse files).
- **Total repository allocated size:** ~24 GB (physical disk space actually used).
- **Likely reclaimable size:** ~16 GB (from accidental DerivedData copies inside benchmarks, and other build folders).
- **GUI’s 143 GB figure:** This is highly inaccurate for actual disk usage, as it calculates the logical size of sparse files (specifically `v8.data` and `v8.index`) instead of their physically allocated block sizes. 
- **Duplicate rows:** The GUI’s duplicate rows were not a bug, but rather multiple distinct benchmark output directories (e.g., `continuous_visibility`, `acceptance_latency`, `screen_context`) that each contained their own full copy of `DerivedData/CompilationCache.noindex/.../v8.data`. 

## Largest Directories
1. `devtools/` (~12 GB allocated)
2. `build/` (~5.1 GB allocated)
3. `.build_derived_data/` (~2.3 GB allocated)
4. `devtools/reports/benchmark_artifacts/` (~12 GB allocated, containing multiple DerivedData folders)

## Largest Files
- `devtools/reports/benchmark_artifacts/acceptance_latency/DerivedData/CompilationCache.noindex/generic/v1.1/v8.data` (17.1 GB logical, 128 KB allocated)
- `devtools/reports/benchmark_artifacts/screen_context/DerivedData/CompilationCache.noindex/generic/v1.1/v8.data` (17.1 GB logical, 128 KB allocated)
- `build/DerivedData/CompilationCache.noindex/generic/v1.1/v8.data` (17.1 GB logical, 128 KB allocated)

## v8.data and v8.index Investigation
- **Full paths:** Occur within any `DerivedData` folder at `DerivedData/CompilationCache.noindex/generic/v1.1/v8.data` and `v8.index`.
- **Purpose:** Apple Clang / LLVM uses these as a persistent caching mechanism for module compilations.
- **Origin:** Generated automatically by `xcodebuild`.
- **Logical versus physical size:** They are created as sparse files. Their logical size is instantly mapped to ~17.1 GB (`v8.data`) and ~8.5 GB (`v8.index`), but their physically allocated size is only the blocks actually written to (e.g., 128 KB).
- **Duplicate analysis:** They are completely distinct sparse files, created separately during each benchmark's isolated `xcodebuild` invocation because the scripts explicitly created separate `DerivedData` caches.

## Root Cause
- **Exact responsible scripts:** The automated benchmark scripts inside `devtools/benchmarks/`:
  - `run_acceptance_behavior_benchmark.sh`
  - `run_acceptance_latency_benchmark.sh`
  - `run_continuous_visibility_benchmark.sh`
  - `run_prefix_consumption_benchmark.sh`
  - `run_safari_product_benchmark.sh`
  - `run_screen_context_benchmark.sh`
- **Evidence:** These scripts hardcoded `-derivedDataPath "$ARTIFACT_DIR/DerivedData"`, placing Xcode build caches permanently into the report artifact folders without deleting them afterward. `run_screen_context_benchmark.sh` explicitly skipped `DerivedData` during its cleanup loop.

## Prevention Fix
- **Files modified:** All 6 of the above benchmark shell scripts.
- **Behavioral change:** Changed `-derivedDataPath` to target a secure, uniquely generated temporary directory in `$TMPDIR` using `mktemp -d`.
- **Cleanup safety checks:** Added a `trap` that ensures the directory is properly deleted upon completion (`EXIT`, `INT`, `TERM`), only if the path resolves to a valid temporary directory and avoids system roots like `/` or `$HOME`.

## Local Model Assets
- **Exact model files:** `TypeFlow/llama.cpp/models/ggml-vocab-*.gguf` (e.g., `ggml-vocab-llama-bpe.gguf`, `ggml-vocab-qwen2.gguf`, etc.)
- **Size:** ~70 MB total physically.
- **Whether required:** Required (they provide the vocabulary and tokenization necessary for `llama.cpp`).
- **Recommendation:** **RETAIN**

## Proposed Deletion Manifest
*(NOT EXECUTED — AWAITING USER APPROVAL)*

| ID | Exact absolute path | Item type | Logical size | Allocated size | Rebuildable? | Risk level | Recommendation | Reason | Command |
|---|---|---|---|---|---|---|---|---|---|
| 1 | `$ROOT/devtools/reports/benchmark_artifacts/acceptance_latency/DerivedData` | Cache | ~26 GB | ~2.0 GB | Yes | Low | DELETE AFTER CLOSING XCODE | Generated cache accidentally retained in benchmark artifacts | `rm -rf devtools/reports/benchmark_artifacts/acceptance_latency/DerivedData` |
| 2 | `$ROOT/devtools/reports/benchmark_artifacts/continuous_visibility/DerivedData` | Cache | ~26 GB | ~2.3 GB | Yes | Low | DELETE AFTER CLOSING XCODE | Generated cache accidentally retained in benchmark artifacts | `rm -rf devtools/reports/benchmark_artifacts/continuous_visibility/DerivedData` |
| 3 | `$ROOT/devtools/reports/benchmark_artifacts/prefix_consumption/DerivedData` | Cache | ~26 GB | ~2.3 GB | Yes | Low | DELETE AFTER CLOSING XCODE | Generated cache accidentally retained in benchmark artifacts | `rm -rf devtools/reports/benchmark_artifacts/prefix_consumption/DerivedData` |
| 4 | `$ROOT/devtools/reports/benchmark_artifacts/screen_context/DerivedData` | Cache | ~26 GB | ~1.6 GB | Yes | Low | DELETE AFTER CLOSING XCODE | Generated cache accidentally retained in benchmark artifacts | `rm -rf devtools/reports/benchmark_artifacts/screen_context/DerivedData` |
| 5 | `$ROOT/devtools/reports/benchmark_artifacts/DerivedData` | Cache | ~26 GB | ~2.3 GB | Yes | Low | DELETE AFTER CLOSING XCODE | Generated cache accidentally retained in benchmark artifacts | `rm -rf devtools/reports/benchmark_artifacts/DerivedData` |
| 6 | `$ROOT/build` | Build folder | ~27 GB | ~5.1 GB | Yes | Low | DELETE AFTER CLOSING XCODE | Leftover generic build outputs | `rm -rf build` |
| 7 | `$ROOT/.build_derived_data` | Build folder | ~26 GB | ~2.3 GB | Yes | Low | DELETE AFTER CLOSING XCODE | Leftover generic build outputs | `rm -rf .build_derived_data` |

*Estimated real space reclaimed: ~17.9 GB*

## Items That Must Be Preserved
- `TypeFlow/llama.cpp/models/*.gguf`
- Source code files and `.json` logs inside `benchmark_artifacts/`
- `.xcode-spm/` (unless explicitly refreshing packages, it saves bandwidth)
- Any manually downloaded `gguf` files within `venv_gguf/` (none were found currently, but the folder is standard)

## Manual Approval Required
No files have been moved or deleted. Awaiting explicit user approval before executing the deletion manifest above.
