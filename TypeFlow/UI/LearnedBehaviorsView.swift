import SwiftUI

struct LearnedBehaviorsView: View {
    @State private var behaviors = AdaptivePatternLearner.shared.behaviors
    @State private var newClipboardTrigger: String = ""
    @State private var newStopWord: String = ""
    @State private var newAbbreviationShort: String = ""
    @State private var newAbbreviationExpanded: String = ""
    
    @AppStorage("adaptiveStopWordsEnabled") private var adaptiveStopWordsEnabled = true
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Adaptive Pattern Learning")
                    .font(.title2)
                    .bold()
                
                Text("TypeFlow learns from your typing history to predict when you want to paste a link, and which words to avoid autocomplete on. You can manage these learned behaviors below.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Divider()
                
                HStack(spacing: 20) {
                    VStack(alignment: .leading) {
                        Text("Clipboard Triggers")
                            .font(.headline)
                        Text("Phrases that trigger a smart paste.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        HStack {
                            TextField("New trigger...", text: $newClipboardTrigger)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                            Button(action: {
                                if !newClipboardTrigger.isEmpty {
                                    AdaptivePatternLearner.shared.addClipboardTrigger(trigger: newClipboardTrigger)
                                    newClipboardTrigger = ""
                                    refresh()
                                }
                            }) { Image(systemName: "plus") }
                        }
                        
                        List {
                            ForEach(behaviors.clipboardTriggers, id: \.self) { trigger in
                                HStack {
                                    Text(trigger)
                                    Spacer()
                                    Button(action: {
                                        AdaptivePatternLearner.shared.deleteBehavior(trigger: trigger)
                                        refresh()
                                    }) {
                                        Image(systemName: "trash")
                                            .foregroundColor(.red)
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                }
                            }
                        }
                        .frame(height: 150)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.3), lineWidth: 1))
                    }
                    
                    VStack(alignment: .leading) {
                        HStack {
                            Text("Learned Stop-Words")
                                .font(.headline)
                            Spacer()
                            Toggle("Enable Adaptive Stop-Words", isOn: $adaptiveStopWordsEnabled)
                                .toggleStyle(.switch)
                                .scaleEffect(0.8)
                        }
                        
                        Text("Words that suppress autocomplete.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        HStack {
                            TextField("New stop-word...", text: $newStopWord)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                            Button(action: {
                                if !newStopWord.isEmpty {
                                    AdaptivePatternLearner.shared.addStopWord(word: newStopWord)
                                    newStopWord = ""
                                    refresh()
                                }
                            }) { Image(systemName: "plus") }
                        }
                        
                        List {
                            ForEach(behaviors.stopWords, id: \.self) { word in
                                HStack {
                                    Text(word)
                                    Spacer()
                                    Button(action: {
                                        AdaptivePatternLearner.shared.deleteStopWord(word: word)
                                        refresh()
                                    }) {
                                        Image(systemName: "trash")
                                            .foregroundColor(.red)
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                }
                            }
                        }
                        .frame(height: 150)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.3), lineWidth: 1))
                    }
                }
                
                Divider()
                
                VStack(alignment: .leading) {
                    Text("Abbreviation Expansions")
                        .font(.headline)
                    Text("Auto-replace shortcodes with full words instantly while typing.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    HStack {
                        TextField("Short (e.g. elts)", text: $newAbbreviationShort)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                        TextField("Expanded (e.g. elements)", text: $newAbbreviationExpanded)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                        Button(action: {
                            if !newAbbreviationShort.isEmpty && !newAbbreviationExpanded.isEmpty {
                                AdaptivePatternLearner.shared.addAbbreviation(short: newAbbreviationShort, expanded: newAbbreviationExpanded)
                                newAbbreviationShort = ""
                                newAbbreviationExpanded = ""
                                refresh()
                            }
                        }) { Image(systemName: "plus") }
                    }
                    
                    List {
                        ForEach(behaviors.abbreviationExpansions.keys.sorted(), id: \.self) { short in
                            HStack {
                                Text(short)
                                    .font(.system(.body, design: .monospaced))
                                Image(systemName: "arrow.right").foregroundColor(.secondary)
                                Text(behaviors.abbreviationExpansions[short] ?? "")
                                Spacer()
                                Button(action: {
                                    AdaptivePatternLearner.shared.deleteAbbreviation(short: short)
                                    refresh()
                                }) {
                                    Image(systemName: "trash")
                                        .foregroundColor(.red)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                    }
                    .frame(height: 150)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.3), lineWidth: 1))
                }
            }
            .padding(40)
        }
        .onAppear {
            refresh()
        }
    }
    
    private func refresh() {
        self.behaviors = AdaptivePatternLearner.shared.behaviors
    }
}
