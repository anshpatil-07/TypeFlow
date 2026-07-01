import Foundation

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
        let leadingWhitespace = String(candidate.prefix { $0.isWhitespace })
        let withoutLeadingWhitespace = String(candidate.dropFirst(leadingWhitespace.count))

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
        if loopCheck.rejected {
            return ContinuationContract(suggestion: "", decision: .rejected, reason: "repeatedTokenLoop")
        }
        if loopCheck.truncated {
            return ContinuationContract(suggestion: loopCheck.text, decision: .truncated, reason: "repeatedTokenLoop")
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

        return ContinuationContract(suggestion: candidate, decision: .accepted, reason: "validContinuation")
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
                return ("", false, true)
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

let cases = [
    Case(name: "pure overlap after word", active: "the quick brown", raw: " brown", decision: .rejected, reason: "pureOverlap", suggestion: ""),
    Case(name: "duplicate phrase overlap", active: "...quality and then co", raw: "and then co", decision: .rejected, reason: "pureOverlap", suggestion: ""),
    Case(name: "duplicate partial overlap", active: "...with a fe", raw: " fe", decision: .rejected, reason: "pureOverlap", suggestion: ""),
    Case(name: "punctuation only", active: "...writes a caref", raw: ".", decision: .rejected, reason: "punctuationOnly", suggestion: ""),
    Case(name: "repeated token loop", active: "a few", raw: "ordinary ordinary ordinary", decision: .rejected, reason: "repeatedTokenLoop", suggestion: ""),
    Case(name: "valid after-space", active: "the quick ", raw: "brown fox", decision: .accepted, reason: "validContinuation", suggestion: "brown fox"),
    Case(name: "valid mid-word healing", active: "autocom", raw: "autocomplete works", decision: .accepted, reason: "validContinuation", suggestion: "plete works"),
    Case(name: "leading whitespace removed mid-word by contract", active: "hello", raw: " world", decision: .accepted, reason: "validContinuation", suggestion: "world"),
    Case(name: "whitespace only", active: "hello", raw: "   \t", decision: .rejected, reason: "whitespaceOnly", suggestion: ""),
    Case(name: "punctuation plus meaningful text", active: "hello", raw: ", world", decision: .accepted, reason: "validContinuation", suggestion: ", world"),
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
