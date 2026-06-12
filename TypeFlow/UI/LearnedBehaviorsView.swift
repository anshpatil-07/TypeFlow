import SwiftUI

struct LearnedBehaviorsView: View {
    @State private var behaviors = AdaptivePatternLearner.shared.behaviors
    
    var body: some View {
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
                    .frame(height: 200)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.3), lineWidth: 1))
                }
                
                VStack(alignment: .leading) {
                    Text("Learned Stop-Words")
                        .font(.headline)
                    Text("Words that suppress autocomplete.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
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
                    .frame(height: 200)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.3), lineWidth: 1))
                }
            }
        }
        .padding(40)
        .onAppear {
            refresh()
        }
    }
    
    private func refresh() {
        self.behaviors = AdaptivePatternLearner.shared.behaviors
    }
}
