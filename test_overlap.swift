import Foundation

let activeLine = "Hello world"
let completion = " world"
var processedCompletion = completion.trimmingCharacters(in: .whitespacesAndNewlines)

var overlapLength = 0
let maxOverlap = min(activeLine.count, processedCompletion.count)
if maxOverlap > 0 {
    for i in (1...maxOverlap).reversed() {
        let suffix = activeLine.suffix(i)
        let prefix = processedCompletion.prefix(i)
        if suffix.lowercased() == prefix.lowercased() {
            overlapLength = i
            break
        }
    }
}
if overlapLength > 0 {
    processedCompletion = String(processedCompletion.dropFirst(overlapLength))
}

print("overlap: \(overlapLength), processed: '\(processedCompletion)'")
