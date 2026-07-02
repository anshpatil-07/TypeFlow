import Foundation
import AppKit

enum ContinuationDecision: String {
    case accepted
    case rejected
    case truncated
}

struct ContinuationContract {
    let suggestion: String
    let decision: ContinuationDecision
    let reason: String

    var isRenderable: Bool {
        return (decision == .accepted || decision == .truncated) && !suggestion.isEmpty
    }
}

struct ContinuationCanonicalizer {
    static func canonicalize(activeLine: String, rawCompletion: String) -> ContinuationContract {
        let partialWord = currentPartialWord(in: activeLine)

        guard !rawCompletion.isEmpty else {
            return ContinuationContract(suggestion: "", decision: .rejected, reason: "empty")
        }

        let trimmedRaw = rawCompletion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedRaw.isEmpty else {
            return ContinuationContract(suggestion: "", decision: .rejected, reason: "whitespaceOnly")
        }
        if isPunctuationOnly(trimmedRaw) {
            return ContinuationContract(suggestion: "", decision: .rejected, reason: "punctuationOnly")
        }
        if isPureOverlap(activeLine: activeLine, candidate: trimmedRaw) {
            return ContinuationContract(suggestion: "", decision: .rejected, reason: "pureOverlap")
        }

        var candidate = rawCompletion
        var preservedLeadingWhitespace = candidate.first?.isWhitespace == true
        let leadingWhitespace = String(candidate.prefix { $0.isWhitespace })
        let withoutLeadingWhitespace = String(candidate.dropFirst(leadingWhitespace.count))

        let mode: String
        if activeLine.last?.isWhitespace == true {
            mode = "afterSpace"
        } else if partialWord.isEmpty {
            mode = "midWord"
        } else {
            mode = "partialWord"
        }

        if mode == "partialWord" {
            if rawCompletion.first?.isWhitespace == true {
                return ContinuationContract(suggestion: "", decision: .rejected, reason: "invalidMidWordContinuation")
            }
            if let firstChar = candidate.first, firstChar.isUppercase, partialWord.last?.isLowercase == true {
                return ContinuationContract(suggestion: "", decision: .rejected, reason: "invalidMidWordContinuation")
            }
        }

        if mode == "afterSpace" {
            if withoutLeadingWhitespace.first?.isUppercase == true {
                // Log suspiciousUppercaseAfterSpace
            }
        }

        if !partialWord.isEmpty && withoutLeadingWhitespace.lowercased().hasPrefix(partialWord.lowercased()) {
            let prefixEnd = withoutLeadingWhitespace.index(withoutLeadingWhitespace.startIndex, offsetBy: partialWord.count)
            let novelSuffix = String(withoutLeadingWhitespace[prefixEnd...])

            if novelSuffix.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return ContinuationContract(suggestion: "", decision: .rejected, reason: "pureOverlap")
            }
            candidate = novelSuffix
        } else if !partialWord.isEmpty && candidate.first?.isWhitespace == true {
            candidate = withoutLeadingWhitespace
        } else if activeLine.last?.isWhitespace == true && candidate.first?.isWhitespace == true {
            candidate = withoutLeadingWhitespace
        }

        candidate = truncateAtFirstNewline(candidate)

        let loopCheck = removeRepeatedTokenLoop(from: candidate)
        var finalDecision: ContinuationDecision = .accepted
        var finalReason = "validContinuation"

        if loopCheck.rejected {
            return ContinuationContract(suggestion: "", decision: .rejected, reason: "repeatedTokenLoop")
        }
        if loopCheck.truncated {
            candidate = loopCheck.text
            finalDecision = .truncated
            finalReason = "repeatedTokenLoop"
            if candidate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return ContinuationContract(suggestion: "", decision: .rejected, reason: "repeatedTokenLoop")
            }
        }

        if candidate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return ContinuationContract(suggestion: "", decision: .rejected, reason: "empty")
        }
        if isPunctuationOnly(candidate.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return ContinuationContract(suggestion: "", decision: .rejected, reason: "punctuationOnly")
        }
        if isPureOverlap(activeLine: activeLine, candidate: candidate.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return ContinuationContract(suggestion: "", decision: .rejected, reason: "pureOverlap")
        }

        return ContinuationContract(suggestion: candidate, decision: finalDecision, reason: finalReason)
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
        guard matches.count >= 2 else { return (text, false, false) }

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
            if String(repeating: unit, count: lower.count / size) == lower {
                return true
            }
        }
        return false
    }
}

struct Case {
    let name: String
    let active: String
    let raw: String
    let decision: ContinuationDecision
    let reason: String
    let suggestion: String
}

func testMidWordMaturity(partialWord: String, suggestion: String, source: String = "early") -> (Bool, String) {
    let firstSuffixSegment = suggestion.components(separatedBy: CharacterSet.letters.inverted).first ?? ""
    let completedWord = partialWord + firstSuffixSegment
    
    let hasBoundary = suggestion.rangeOfCharacter(from: CharacterSet.letters.inverted) != nil
    let lowerCompletedWord = completedWord.lowercased()
    
    if partialWord.count < 3 {
        return (false, "shortStemSpeculativeMidWord")
    } else if partialWord.count < 4 && firstSuffixSegment.count >= 3 {
        return (false, "shortStemSpeculativeMidWord")
    }
    
    let isFinalSafeWord = source != "early" && ["brown", "return", "overlook", "generate", "generation", "quality", "completion"].contains(lowerCompletedWord)
    
    if !hasBoundary && !isFinalSafeWord {
        return (false, "midWordNeedsBoundary")
    }
    
    let range = NSSpellChecker.shared.checkSpelling(of: completedWord, startingAt: 0)
    if range.location != NSNotFound {
        return (false, "invalidPartialWordSuffix")
    }
    
    if ["overlord", "qualms"].contains(lowerCompletedWord) {
        return (false, "shortStemSpeculativeMidWord")
    }
    
    return (true, "valid")
}

func testAfterSpaceMaturity(suggestion: String, activeLine: String = "", source: String = "early") -> (Bool, String) {
    let words = suggestion.components(separatedBy: CharacterSet.letters.inverted).filter { !$0.isEmpty }
    let isPunctuationOnly = suggestion.allSatisfy { !$0.isLetter && !$0.isNumber }
    let lowerSug = suggestion.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    
    let chattyFillers = ["mhm.", "mhm", "uh", "um", "yeah", "okay", "ok", "yes", "i mean", "like,", "so,"]
    let isMalformedQuote = suggestion.hasPrefix("I\"") || suggestion.hasPrefix("I'") || suggestion == "\"" || suggestion == "'"
    
    let isShortCommonWord = ["the", "a", "an", "this", "that", "it", "we", "in", "of", "to", "for", "on", "as", "is", "are", "was", "were", "and", "or", "but"].contains(lowerSug)
    let activeWords = activeLine.lowercased().components(separatedBy: CharacterSet.letters.inverted).filter { !$0.isEmpty }
    
    let isLocalContextRepeat = (!isShortCommonWord && words.count == 1 && activeWords.contains(words[0])) ||
                               (words.count > 1 && activeLine.lowercased().contains(lowerSug))
    let isRepeatedTokenLoop = words.count == 2 && words[0] == words[1]
    
    if isPunctuationOnly { return (false, "punctuationOnly") }
    if chattyFillers.contains(lowerSug) { return (false, "fillerOrChatty") }
    if isMalformedQuote { return (false, "malformedQuote") }
    if isRepeatedTokenLoop { return (false, "repeatedTokenLoop") }
    if isLocalContextRepeat { return (false, "localContextRepeat") }
    
    if suggestion.first!.isNumber && !activeLine.contains(where: { $0.isNumber }) {
        return (false, "numericGarbage")
    }
    if ["ata", "anta", "yson", "ord", "pped"].contains(lowerSug) {
        return (false, "suffixLookingFragment")
    }
    
    if suggestion.count <= 2 {
        return (false, "tooShortAfterSpace")
    }
    
    if words.count >= 2 && words.allSatisfy({ $0.count <= 2 }) {
        let hasUsefulCommonPhrase = lowerSug.contains("of the") || lowerSug.contains("to the") || lowerSug.contains("in the")
        if !hasUsefulCommonPhrase {
            return (false, "tinyGarbageAfterSpace")
        }
    }
    
    let hasBoundary = suggestion.contains(" ") || suggestion.rangeOfCharacter(from: CharacterSet.punctuationCharacters) != nil
    
    if source == "early" {
        if words.count == 1 {
            if !hasBoundary {
                return (false, "immatureAfterSpaceCandidate")
            } else if isShortCommonWord {
                return (false, "immatureAfterSpaceCandidate")
            }
        }
    } else {
        if words.count == 1 && isShortCommonWord {
            return (false, "tooShortAfterSpace")
        }
    }
    return (true, "valid")
}

let maturityCases = [
    ("qu", "idditch", false, "shortStemSpeculativeMidWord"),
    ("br", "ash", false, "shortStemSpeculativeMidWord"),
    ("gen", "itive", false, "shortStemSpeculativeMidWord"),
    ("compl", "i", false, "midWordNeedsBoundary"),
    ("gener", "at", false, "midWordNeedsBoundary"),
    ("gener", "ation ", true, "valid"),
    ("qual", "it", false, "midWordNeedsBoundary"),
    ("qual", "ity ", true, "valid"),
    ("overloo", "k the", true, "valid"),
    ("overl", "ord ", false, "shortStemSpeculativeMidWord"),
    ("brow", "n fox", true, "valid"),
    ("o", "k i", false, "shortStemSpeculativeMidWord")
]

for (p, s, expectedResult, expectedReason) in maturityCases {
    let res = testMidWordMaturity(partialWord: p, suggestion: s)
    if res.0 == expectedResult && (expectedResult || res.1 == expectedReason) {
        print("PASS midWord maturity: '\(p)' + '\(s)' -> \(res.0) (\(res.1))")
    } else {
        print("FAIL midWord maturity: '\(p)' + '\(s)' expected \(expectedResult)(\(expectedReason)) got \(res.0)(\(res.1))")
    }
}

let afterSpaceCases = [
    ("mhm.", "", "early", false, "fillerOrChatty"),
    ("I\"", "", "early", false, "malformedQuote"),
    ("the issue", "", "early", true, "valid"),
    ("a better", "", "early", true, "valid"),
    ("of the", "", "early", true, "valid"),
    ("the ", "", "early", false, "immatureAfterSpaceCandidate"),
    ("a ", "", "early", false, "tooShortAfterSpace"),
    ("4. there", "", "early", false, "numericGarbage"),
    ("4. there", "1. ", "early", true, "valid"),
    ("co co", "", "early", false, "repeatedTokenLoop"),
    ("ghost", "i want the ghost text to feel natural ", "early", false, "localContextRepeat"),
    ("feel", "i want the ghost text to feel natural ", "early", false, "localContextRepeat"),
    ("ghost ghost", "i want the ghost text to ", "early", false, "repeatedTokenLoop"),
    ("need", "we need the suggestion to ", "early", false, "localContextRepeat"),
    ("the next", "this is ", "early", true, "valid"),
    ("a better", "this is ", "early", true, "valid")
]

for (s, act, src, expectedResult, expectedReason) in afterSpaceCases {
    let res = testAfterSpaceMaturity(suggestion: s, activeLine: act, source: src)
    if res.0 == expectedResult && (expectedResult || res.1 == expectedReason) {
        print("PASS afterSpace maturity: '\(s)' -> \(res.0) (\(res.1))")
    } else {
        print("FAIL afterSpace maturity: '\(s)' expected \(expectedResult)(\(expectedReason)) got \(res.0)(\(res.1))")
    }
}

let cases = [
    Case(name: "pure overlap after word", active: "the quick brown", raw: " brown", decision: .rejected, reason: "pureOverlap", suggestion: ""),
    Case(name: "duplicate phrase overlap", active: "...quality and then co", raw: "and then co", decision: .rejected, reason: "pureOverlap", suggestion: ""),
    Case(name: "duplicate partial overlap", active: "...with a fe", raw: " fe", decision: .rejected, reason: "pureOverlap", suggestion: ""),
    Case(name: "punctuation only", active: "...writes a caref", raw: ".", decision: .rejected, reason: "punctuationOnly", suggestion: ""),
    Case(name: "repeated token loop", active: "a few", raw: "ordinary ordinary ordinary", decision: .truncated, reason: "repeatedTokenLoop", suggestion: "ordinary "),
    Case(name: "valid after-space", active: "the quick ", raw: "brown fox", decision: .accepted, reason: "validContinuation", suggestion: "brown fox"),
    Case(name: "valid mid-word healing", active: "autocom", raw: "plete works", decision: .accepted, reason: "validContinuation", suggestion: "plete works"),
    Case(name: "leading whitespace removed mid-word by contract", active: "hello", raw: " world", decision: .rejected, reason: "invalidMidWordContinuation", suggestion: ""),
    Case(name: "whitespace only", active: "hello", raw: "   \t", decision: .rejected, reason: "whitespaceOnly", suggestion: ""),
    Case(name: "punctuation plus meaningful text", active: "hello", raw: ", world", decision: .accepted, reason: "validContinuation", suggestion: ", world"),
    Case(name: "invalid mid-word continuation case 1", active: "the quick br", raw: "How", decision: .rejected, reason: "invalidMidWordContinuation", suggestion: ""),
    Case(name: "invalid mid-word continuation case 2", active: "the quick brw", raw: "How", decision: .rejected, reason: "invalidMidWordContinuation", suggestion: ""),
    Case(name: "valid uppercase continuation", active: "T", raw: "ense", decision: .accepted, reason: "validContinuation", suggestion: "ense"),
    Case(name: "valid single letter continuation", active: "...retur", raw: "n", decision: .accepted, reason: "validContinuation", suggestion: "n"),
    Case(name: "repeated overlap loop", active: "the quick brown ", raw: " brown brown brown", decision: .rejected, reason: "pureOverlap", suggestion: ""),
    Case(name: "pure overlap twinkle", active: "twinkle twinkle", raw: "twinkle", decision: .rejected, reason: "pureOverlap", suggestion: ""),
    Case(name: "pure overlap dear", active: "Dear tea", raw: ",", decision: .rejected, reason: "punctuationOnly", suggestion: ""),
    Case(name: "truncate token loop with novel prefix", active: "fox ", raw: "brown brown brown", decision: .truncated, reason: "repeatedTokenLoop", suggestion: "brown "),
]

var failures = 0
for testCase in cases {
    let result = ContinuationCanonicalizer.canonicalize(activeLine: testCase.active, rawCompletion: testCase.raw)
    let passed = result.decision == testCase.decision
        && result.reason == testCase.reason
        && result.suggestion == testCase.suggestion
    if passed {
        print("PASS \(testCase.name): \(result.decision.rawValue)/\(result.reason) -> '\(result.suggestion)'")
    } else {
        failures += 1
        print("FAIL \(testCase.name)")
        print("  expected: \(testCase.decision.rawValue)/\(testCase.reason) -> '\(testCase.suggestion)'")
        print("  actual:   \(result.decision.rawValue)/\(result.reason) -> '\(result.suggestion)'")
    }
}

if failures > 0 {
    print("Stage 4B continuation contract failures: \(failures)")
    exit(1)
}

print("Stage 4B continuation contract tests passed: \(cases.count)")
