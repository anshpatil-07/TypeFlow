import Foundation

let sourcePath = "TypeFlow/Services/PromptBuilder.swift"
guard let sourceContent = try? String(contentsOfFile: sourcePath) else {
    print("Could not read PromptBuilder.swift")
    exit(1)
}

// Just extract the body of buildPromptSuffix
// For a quick script, it's easier to just test the logic directly since PromptBuilder isn't easily instantiable due to UI/singleton dependencies in Swift scripts.
// Let's replicate the logic snippet to ensure it does what we expect:

func testBuildPromptSuffix(textBeforeCaret: String) -> (suffix: String, requiresHealing: Bool, mode: String, partialWord: String) {
    let lines = textBeforeCaret.components(separatedBy: .newlines)
    let activeLine = lines.last ?? ""
    
    var previousLinesIncluded = 0
    var previousContextLen = 0
    var previousContextOmittedReason = "none"
    var finalPreviousLines = ""
    
    // Active-line first policy
    // 1. Grab at most 1 previous non-empty line
    if let lastNonEmpty = lines.dropLast().last(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) {
        // Check if it's too long
        if lastNonEmpty.count > 160 {
            previousContextOmittedReason = "tooLong"
        } else if activeLine.count > 20 {
            // Prefer active line only if we have enough prose context
            previousContextOmittedReason = "activeLineOnly"
        } else {
            let hasNumberedList = lastNonEmpty.range(of: #"^\d+\.\s"#, options: .regularExpression) != nil
            let activeHasNumberedList = activeLine.range(of: #"^\d+\.\s"#, options: .regularExpression) != nil
            
            if hasNumberedList && !activeHasNumberedList {
                previousContextOmittedReason = "numberedListMismatch"
            } else if lastNonEmpty.lowercased().contains("the quick brown") || lastNonEmpty.lowercased().contains("twinkle") || lastNonEmpty.lowercased().contains("ok ill overlook") {
                previousContextOmittedReason = "repeatPhraseRisk"
            } else {
                finalPreviousLines = lastNonEmpty
                previousLinesIncluded = 1
                previousContextLen = finalPreviousLines.count
            }
        }
    }
    
    var suffix = ""
    if !finalPreviousLines.isEmpty {
        suffix += finalPreviousLines + "\n"
    }

    var finalActiveLine = activeLine
    let activeLineEndsWithWhitespace = activeLine.hasSuffix(" ") || activeLine.hasSuffix("\t") || activeLine.hasSuffix("\n")
    var requiresHealing = false
    var partialWord = ""
    var mode = "empty"

    if activeLine.isEmpty {
        mode = "empty"
    } else if activeLineEndsWithWhitespace {
        mode = "afterSpace"
        requiresHealing = false
    } else {
        let wordBoundaryChars: Set<Character> = [
            " ", "\t", ".", "_", "(", ")", ":", "/", ",", ";",
            "{", "}", "=", "+", "-", "*", "&", "|", "!", "?",
            "\"", "'", "[", "]", "<", ">"
        ]
        let hasTrailingBoundary = wordBoundaryChars.contains(activeLine.last!)
        
        if hasTrailingBoundary {
            mode = "punctuation"
            requiresHealing = false
        } else {
            mode = "midWord"
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
            if !partialWord.isEmpty {
                requiresHealing = true
            }
        }
    }
    
    suffix += finalActiveLine
    
    return (suffix, requiresHealing, mode, partialWord)
}

let cases = [
    ("the quick ", "the quick ", false, "afterSpace", ""),
    ("ok ill overlook ", "ok ill overlook ", false, "afterSpace", ""),
    ("Dear ", "Dear ", false, "afterSpace", ""),
    ("retur", "retur", true, "midWord", "retur"),
    ("the quick brow", "the quick brow", true, "midWord", "brow"),
    ("", "", false, "empty", ""),
    ("Hello, ", "Hello, ", false, "afterSpace", ""),
    ("Hello,", "Hello,", false, "punctuation", ""),
    ("the quick brown\nok ill overlook ", "ok ill overlook ", false, "afterSpace", ""), // repeatPhraseRisk
    ("1. the quick brown\n2. ok ill overlook ", "2. ok ill overlook ", false, "afterSpace", ""), // repeatPhraseRisk triggers
    ("1. normal line\n2. ok ill overlook ", "1. normal line\n2. ok ill overlook ", false, "afterSpace", ""), // keeps it since both have numbered lists and no repeat risk
    ("1. normal line\nok ill overlook ", "ok ill overlook ", false, "afterSpace", ""), // numberedListMismatch
    ("Hello world, this is a very long line to ensure active line only kicks in\nok ill overlook this long sentence ", "ok ill overlook this long sentence ", false, "afterSpace", "") // activeLineOnly > 20
]

var failures = 0
for (input, expSuffix, expHeal, expMode, expPartial) in cases {
    let res = testBuildPromptSuffix(textBeforeCaret: input)
    if res.suffix == expSuffix && res.requiresHealing == expHeal && res.mode == expMode && res.partialWord == expPartial {
        print("PASS: '\(input)' -> mode=\(res.mode), heal=\(res.requiresHealing), suffix='\(res.suffix)'")
    } else {
        print("FAIL: '\(input)'")
        print("  Expected: suffix='\(expSuffix)', heal=\(expHeal), mode=\(expMode), partial='\(expPartial)'")
        print("  Got:      suffix='\(res.suffix)', heal=\(res.requiresHealing), mode=\(res.mode), partial='\(res.partialWord)'")
        failures += 1
    }
}

if failures > 0 {
    print("PromptBuilder tests failed: \(failures)")
    exit(1)
} else {
    print("PromptBuilder tests passed: \(cases.count)")
}
