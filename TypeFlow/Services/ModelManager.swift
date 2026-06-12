import Foundation
import Combine
import SwiftUI
import Hub

enum ModelStatus: String, Codable {
    case notDownloaded
    case downloading
    case downloaded
}

struct MLXModel: Identifiable, Codable {
    var id: String
    var name: String
    var status: ModelStatus
    var progress: Double
    var isCustom: Bool = false
    
    var isDownloaded: Bool {
        return status == .downloaded
    }
}

@MainActor
class ModelManager: ObservableObject {
    @Published var models: [MLXModel] = []
    @AppStorage("customModelsData") private var customModelsData: Data = Data()
    
    let recommendedModels: [MLXModel] = [
        MLXModel(id: "mlx-community/gemma-4-E4B-it-4bit", name: "Gemma 4 E4B (4-bit)", status: .notDownloaded, progress: 0.0),
        MLXModel(id: "mlx-community/gemma-4-12B-it-4bit", name: "Gemma 4 12B (4-bit)", status: .notDownloaded, progress: 0.0),
        MLXModel(id: "mlx-community/Meta-Llama-3-8B-Instruct-4bit", name: "Llama 3 8B (4-bit)", status: .notDownloaded, progress: 0.0),
        MLXModel(id: "mlx-community/Phi-3-mini-4k-instruct-4bit", name: "Phi-3 Mini (4-bit)", status: .notDownloaded, progress: 0.0),
        MLXModel(id: "mlx-community/Qwen2.5-1.5B-Instruct-4bit", name: "Qwen 2.5 1.5B (4-bit)", status: .notDownloaded, progress: 0.0),
        MLXModel(id: "mlx-community/Qwen2.5-7B-Instruct-4bit", name: "Qwen 2.5 7B (4-bit)", status: .notDownloaded, progress: 0.0),
        MLXModel(id: "mlx-community/Mistral-7B-Instruct-v0.3-4bit", name: "Mistral v0.3 7B (4-bit)", status: .notDownloaded, progress: 0.0)
    ]
    
    init() {
        loadModels()
    }
    
    func loadModels() {
        var allModels = recommendedModels
        
        if let customModels = try? JSONDecoder().decode([MLXModel].self, from: customModelsData) {
            allModels.append(contentsOf: customModels)
        }
        
        // Verify download status for all models
        let cacheDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".cache/huggingface/hub")
        for i in 0..<allModels.count {
            let modelId = allModels[i].id
            let folderName = "models--" + modelId.replacingOccurrences(of: "/", with: "--")
            let modelURL = cacheDir.appendingPathComponent(folderName)
            if FileManager.default.fileExists(atPath: modelURL.path) {
                allModels[i].status = .downloaded
                allModels[i].progress = 1.0
            }
        }
        
        self.models = allModels
    }
    
    func addCustomModel(id: String) {
        let cleanId = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanId.isEmpty, !models.contains(where: { $0.id == cleanId }) else { return }
        
        let newModel = MLXModel(id: cleanId, name: cleanId, status: .notDownloaded, progress: 0.0, isCustom: true)
        models.append(newModel)
        saveCustomModels()
        downloadModel(id: cleanId)
    }
    
    private func saveCustomModels() {
        let customs = models.filter { $0.isCustom }
        if let data = try? JSONEncoder().encode(customs) {
            customModelsData = data
        }
    }
    
    func downloadModel(id: String) {
        guard let index = models.firstIndex(where: { $0.id == id }) else { return }
        
        models[index].status = .downloading
        models[index].progress = 0.0
        
        Task {
            do {
                // Try using HubApi to snapshot the repo.
                // We don't have granular byte progress from the static Hub.snapshot in MLX,
                // so we rely on the indeterminate downloading state.
                let _ = try await Hub.snapshot(from: id) { progress in
                    Task { @MainActor in
                        // We could use progress.fractionCompleted if it was accurate for the whole repo,
                        // but it's often per-file or indeterminate. We just keep it running.
                    }
                }
                
                await MainActor.run {
                    if let newIndex = self.models.firstIndex(where: { $0.id == id }) {
                        self.models[newIndex].status = .downloaded
                        self.models[newIndex].progress = 1.0
                    }
                }
            } catch {
                print("[TypeFlow] Error downloading model \(id): \(error)")
                await MainActor.run {
                    if let newIndex = self.models.firstIndex(where: { $0.id == id }) {
                        self.models[newIndex].status = .notDownloaded
                        self.models[newIndex].progress = 0.0
                    }
                }
            }
        }
    }
    
    func deleteModel(id: String) {
        guard let index = models.firstIndex(where: { $0.id == id }) else { return }
        
        let cacheDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".cache/huggingface/hub")
        let folderName = "models--" + id.replacingOccurrences(of: "/", with: "--")
        let modelURL = cacheDir.appendingPathComponent(folderName)
        
        do {
            if FileManager.default.fileExists(atPath: modelURL.path) {
                try FileManager.default.removeItem(at: modelURL)
            }
            
            models[index].status = .notDownloaded
            models[index].progress = 0.0
            
            // If it's a custom model and not active, we can also remove it from the list entirely
            if models[index].isCustom && SettingsManager.shared.activeModelId != id {
                models.remove(at: index)
                saveCustomModels()
            }
        } catch {
            print("[TypeFlow] Error deleting model cache: \(error)")
        }
    }
    
    func activateModel(id: String) {
        SettingsManager.shared.activeModelId = id
    }
}
