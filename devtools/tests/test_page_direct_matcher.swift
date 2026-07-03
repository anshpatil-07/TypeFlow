import Foundation

struct PageDirectCandidate {
    let suggestion: String
    let matchChars: Int
    let matchWords: Int
    let matchOffset: Int
    let pageDirectSuffix: String
    let latencyMs: Double
}

func findPageDirectCandidate(activeLine: String, pageText: String) -> PageDirectCandidate? {
    let t0 = CFAbsoluteTimeGetCurrent()
    guard !activeLine.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
          !pageText.isEmpty else { return nil }

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

    let activeLastLine = normActive.components(separatedBy: "\n").last ?? normActive
    let trimmedLine = activeLastLine.trimmingCharacters(in: .whitespacesAndNewlines)
    
    guard trimmedLine.count >= 2 else { return nil }

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

    let lastChar = trimmedLine.last ?? " "
    let isMidWord = !partialWord.isEmpty && (lastChar.isLetter || lastChar.isNumber)

    var suffixesToTry: [(suffix: String, droppedText: String)] = []

    if isMidWord {
        suffixesToTry.append((trimmedLine, ""))
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

        guard let matchRange = lowerPage.range(of: lowerSuffix, options: .backwards) else {
            continue
        }

        let matchChars = suffix.count
        let matchWords = suffix.components(separatedBy: .whitespaces).filter { !$0.isEmpty }.count

        guard matchChars >= 12 || matchWords >= 3 else { continue }

        let matchEnd = normPage.index(normPage.startIndex, offsetBy: normPage.distance(from: normPage.startIndex, to: matchRange.upperBound), limitedBy: normPage.endIndex) ?? normPage.endIndex
        let pageAfterMatch = String(normPage[matchEnd...])

        var wordRemainder = ""
        var remainingPageText = pageAfterMatch

        if !droppedText.isEmpty {
            let pageWordPrefix = pageAfterMatch.prefix(while: { $0.isLetter || $0.isNumber || $0 == "'" || $0 == "-" })
            let pageWord = String(pageWordPrefix)

            guard pageWord.lowercased().hasPrefix(droppedText.lowercased()) else {
                continue
            }

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

        let isCode = remainingPageText.contains("{") || remainingPageText.contains("(") ||
                     remainingPageText.contains("->") || remainingPageText.contains("=>")
        let capLen = isCode ? 120 : 90

        var continuation = (wordRemainder + remainingPageText).trimmingCharacters(in: .init(charactersIn: " \t"))
        
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

// RUN TESTS
let page = "The quick brown fox jumps over the lazy dog. The ghost text issue of typing the same thing as suggestion sometimes refreshes the context. When writing code, if it works, it is good. Lets see if it functions."

struct TestCase {
    let active: String
    let page: String
    let expectedNil: Bool
    let expectedPrefix: String?
}

let cases = [
    TestCase(active: "", page: page, expectedNil: true, expectedPrefix: nil),
    TestCase(active: "o", page: page, expectedNil: true, expectedPrefix: nil),
    TestCase(active: "ok", page: page, expectedNil: true, expectedPrefix: nil),
    TestCase(active: "ok the", page: page, expectedNil: true, expectedPrefix: nil), // too short/no match
    TestCase(active: "lets ", page: page, expectedNil: true, expectedPrefix: nil),
    TestCase(active: "the ghost text issue of typing the same thing as suggestion s", page: page, expectedNil: false, expectedPrefix: "ometimes refreshes the context"),
    TestCase(active: "the ghost text\u{00A0}issue of typing the same thing as suggestion s", page: page.replacingOccurrences(of: " ", with: "\u{00A0}"), expectedNil: false, expectedPrefix: "ometimes refreshes the context"), // unicode/NBSP
    TestCase(active: "Multiple lines before.\nthe ghost text issue of typing the same thing as suggestion s", page: page, expectedNil: false, expectedPrefix: "ometimes refreshes the context"), // multi-line
    TestCase(active: "the ghost text issue of typing the same thing as suggestion s", page: "", expectedNil: true, expectedPrefix: nil), // page text empty
    TestCase(active: "the ghost text issue of typing the same thing as suggestion s", page: String(repeating: page, count: 100), expectedNil: false, expectedPrefix: "ometimes refreshes the context") // page text very long
]

var failed = false
for (idx, tc) in cases.enumerated() {
    let res = findPageDirectCandidate(activeLine: tc.active, pageText: tc.page)
    if tc.expectedNil {
        if res != nil {
            print("FAIL Case \(idx): Expected nil, got '\(res!.suggestion)'")
            failed = true
        } else {
            print("PASS Case \(idx): Got nil as expected")
        }
    } else {
        if let suggestion = res?.suggestion {
            if let expected = tc.expectedPrefix {
                if suggestion.hasPrefix(expected) {
                    print("PASS Case \(idx): Got expected prefix '\(expected)' (full: '\(suggestion)')")
                } else {
                    print("FAIL Case \(idx): Expected prefix '\(expected)', got '\(suggestion)'")
                    failed = true
                }
            } else {
                print("PASS Case \(idx): Got suggestion '\(suggestion)'")
            }
        } else {
            print("FAIL Case \(idx): Expected non-nil, got nil")
            failed = true
        }
    }
}

if failed {
    exit(1)
} else {
    print("ALL TESTS PASSED")
}
