import Foundation

// Example of what we need to inject:
/*
                if !cleanWord.isEmpty, let expansion = AdaptivePatternLearner.shared.behaviors.abbreviationExpansions[cleanWord] {
                    print("[TypeFlow-Debug] abbreviationMatched: true, abbreviationShort: \(cleanWord), abbreviationExpanded: \(expansion)")
                    
                    let deleteCount = cleanWord.count + 1
                    var delimiterStr = ""
                    if keyCode == 49 { delimiterStr = " " }
                    else if keyCode == 48 { delimiterStr = "\t" }
                    else if keyCode == 43 { delimiterStr = "," }
                    else if keyCode == 47 { delimiterStr = "." }
                    
                    // Cancel active ghost
                    PredictionCoordinator.shared.cancelActiveGeneration()
                    CompletionManager.shared.clearCompletion()
                    
                    self.isExpandingAbbreviation = true
                    
                    Task { @MainActor in
                        let textBefore = AccessibilityMonitor.shared.getTextBeforeCaret()
                        let expectedSuffix = cleanWord + delimiterStr
                        
                        if textBefore.hasSuffix(expectedSuffix) {
                            print("[TypeFlow-Debug] transformVerified: true")
                            TextInjector.shared.injectBackspaces(count: deleteCount)
                            TextInjector.shared.injectCharByChar(text: expansion + delimiterStr)
                            
                            // Re-read text to verify it worked and update keystrokeBuffer
                            try? await Task.sleep(nanoseconds: 10_000_000)
                            let newText = AccessibilityMonitor.shared.getTextBeforeCaret()
                            let expectedNewSuffix = expansion + delimiterStr
                            if newText.hasSuffix(expectedNewSuffix) {
                                print("[TypeFlow-Debug] rollbackSucceeded: false, failReason: none (success)")
                                self.keystrokeBuffer = newText
                            } else {
                                print("[TypeFlow-Debug] rollbackAttempted: true, rollbackSucceeded: false, failReason: post-verify-mismatch")
                            }
                        } else {
                            print("[TypeFlow-Debug] transformVerified: false, failReason: suffix-mismatch '\(expectedSuffix)' vs '\(textBefore.suffix(20))'")
                            self.isExpandingAbbreviation = false
                        }
                    }
                    // Update keystrokeBuffer locally for now, since it's asynchronous
                    if let range = keystrokeBuffer.range(of: cleanWord, options: .backwards) {
                        keystrokeBuffer.replaceSubrange(range, with: expansion)
                    }
                }
*/
