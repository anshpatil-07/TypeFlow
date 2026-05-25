import Foundation
import Combine

enum ModelStatus: String {
    case notDownloaded
    case downloading
    case downloaded
}

struct MLXModel: Identifiable {
    var id: String
    var name: String
    var status: ModelStatus
    var progress: Double
    
    var isDownloaded: Bool {
        return status == .downloaded
    }
}

@MainActor
class ModelManager: ObservableObject {
    @Published var models: [MLXModel] = []
    
    init() {
        self.models = [
            MLXModel(id: "gemma-3-4b-it-qat-4bit", name: "Gemma 3 4B (3.2 GB)", status: .notDownloaded, progress: 0.0),
            MLXModel(id: "qwen-2.5-1.5b", name: "Qwen 2.5 1.5B", status: .notDownloaded, progress: 0.0)
        ]
    }
    
    func downloadModel(id: String) {
        guard let index = models.firstIndex(where: { $0.id == id }) else { return }
        
        models[index].status = .downloading
        models[index].progress = 0.0
        
        Task {
            // Simulate download progress
            for i in 1...10 {
                try? await Task.sleep(nanoseconds: 300_000_000)
                await MainActor.run {
                    self.models[index].progress = Double(i) / 10.0
                }
            }
            
            await MainActor.run {
                self.models[index].status = .downloaded
                self.models[index].progress = 1.0
            }
        }
    }
    
    func activateModel(id: String) {
        SettingsManager.shared.activeModelId = id
    }
}
