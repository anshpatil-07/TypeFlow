import Foundation
import Combine
import SwiftUI
import Hub

/// How well a model fits TypeFlow's <150 ms instant-completion target.
enum ModelSpeedTier: String, Codable {
    case instant    // ≤1.5 GB  — reliably < 150 ms on Apple Silicon
    case good       // ≤3 GB   — typically 150-400 ms, acceptable
    case borderline // >3 GB   — may exceed 400 ms; shown greyed
}

enum ModelStatus: String, Codable {
    case notDownloaded
    case downloading
    case downloaded
}

struct MLXModel: Identifiable, Codable {
    var id: String
    var name: String
    var sizeGB: Double?
    var description: String?
    var speedTier: ModelSpeedTier
    var status: ModelStatus
    var progress: Double
    var isCustom: Bool = false

    var isDownloaded: Bool {
        return status == .downloaded
    }

    /// Label shown in the UI badge.
    var speedLabel: String {
        switch speedTier {
        case .instant:    return "⚡ Instant"
        case .good:       return "✓ Good"
        case .borderline: return "⚠ Slow"
        }
    }

    /// Accent colour for the speed badge.
    var speedColor: Color {
        switch speedTier {
        case .instant:    return Color(hue: 0.38, saturation: 0.72, brightness: 0.55)
        case .good:       return Color(hue: 0.58, saturation: 0.65, brightness: 0.60)
        case .borderline: return Color(hue: 0.08, saturation: 0.75, brightness: 0.60)
        }
    }
}

@MainActor
class ModelManager: ObservableObject {
    @Published var models: [MLXModel] = []
    @AppStorage("customModelsData") private var customModelsData: Data = Data()

    // ── Curated list — only models proven capable of real-time autocomplete ──
    // Rule: instant ≤ 1.5 GB · good ≤ 3 GB · borderline > 3 GB (shown but warned)
    let recommendedModels: [MLXModel] = [
        MLXModel(
            id: "mlx-community/Qwen2.5-0.5B-Instruct-4bit",
            name: "Qwen 2.5 0.5B",
            sizeGB: 0.5,
            description: "Tiny footprint, blazing speed. Best for older Macs or anyone who needs completions to feel instantaneous. Lower quality on complex sentences.",
            speedTier: .instant,
            status: .notDownloaded,
            progress: 0.0
        ),
        MLXModel(
            id: "mlx-community/Qwen2.5-1.5B-Instruct-4bit",
            name: "Qwen 2.5 1.5B",
            sizeGB: 1.1,
            description: "Sweet spot for instant completions. Reliably under 150 ms on M1/M2/M3. Recommended for most users.",
            speedTier: .instant,
            status: .notDownloaded,
            progress: 0.0
        ),
        MLXModel(
            id: "mlx-community/gemma-3-1b-it-qat-4bit",
            name: "Gemma 3 1B",
            sizeGB: 0.7,
            description: "Google's compact Gemma 3 model. Extremely fast with solid language quality. Great for everyday prose.",
            speedTier: .instant,
            status: .notDownloaded,
            progress: 0.0
        ),
        MLXModel(
            id: "mlx-community/Phi-3-mini-4k-instruct-4bit",
            name: "Phi-3 Mini",
            sizeGB: 2.3,
            description: "Microsoft's Phi-3 Mini. Strong reasoning and code completion. Slightly slower — best on M2 Pro or better.",
            speedTier: .good,
            status: .notDownloaded,
            progress: 0.0
        ),
        MLXModel(
            id: "mlx-community/gemma-4-E4B-it-4bit",
            name: "Gemma 4 E4B",
            sizeGB: 2.8,
            description: "Google's latest efficient Gemma 4 model. High-quality completions. Best on M2 Pro or M3 with 16 GB+ RAM.",
            speedTier: .good,
            status: .notDownloaded,
            progress: 0.0
        ),
        MLXModel(
            id: "mlx-community/gemma-3-4b-it-qat-4bit",
            name: "Gemma 3 4B",
            sizeGB: 3.2,
            description: "Previous-generation Gemma 4B. Reliable formatting but noticeably slower. May exceed 400 ms on M1 base. Not recommended for real-time autocomplete.",
            speedTier: .borderline,
            status: .notDownloaded,
            progress: 0.0
        ),
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
        
        let newModel = MLXModel(id: cleanId, name: cleanId, speedTier: .good, status: .notDownloaded, progress: 0.0, isCustom: true)
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
                let _ = try await Hub.snapshot(from: id) { progress in
                    Task { @MainActor in
                        if let newIndex = self.models.firstIndex(where: { $0.id == id }) {
                            self.models[newIndex].progress = progress.fractionCompleted
                        }
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
