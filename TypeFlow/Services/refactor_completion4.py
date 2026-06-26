with open("CompletionManager.swift", "r") as f:
    content = f.read()

# 1. Remove init and add smartReplyTask
content = content.replace("""    private init() {
        NotificationCenter.default.addObserver(
            forName: Notification.Name("TypeFlowModelLoadingStateChanged"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self else { return }
            if let isLoading = notification.object as? Bool, !isLoading {
                if let pending = self.pendingCompletionRequest {
                    print("[TypeFlow-Debug] Model finished loading. Firing pending completion request: '\\(pending)'")
                    self.pendingCompletionRequest = nil
                    self.triggerGeneration(with: pending)
                }
            }
        }
    }""", """    private var smartReplyTask: Task<Void, Never>?
    private init() {}""")

# 2. Rename activeLine
content = content.replace("""        let activeLine = self.accessibilityMonitor?.getTextBeforeCaret() ?? bufferFallback""", """        let currentActiveLine = self.accessibilityMonitor?.getTextBeforeCaret() ?? bufferFallback""")
content = content.replace("""hasWordBoundaryBeforeSuffix(activeLine: activeLine, suffix: key)""", """hasWordBoundaryBeforeSuffix(activeLine: currentActiveLine, suffix: key)""")

# 3. Fix smartReply task
content = content.replace("""        let workID = workController.currentWorkID
        workController.replaceGenerationWork(for: workID) { [weak self] in""", """        self.smartReplyTask?.cancel()
        self.smartReplyTask = Task { [weak self] in""")

# 4. Add smartReply cancel
content = content.replace("""    func cancelInflightTasks() {
                rewriteTask?.cancel()
    }""", """    func cancelInflightTasks() {
        rewriteTask?.cancel()
        smartReplyTask?.cancel()
    }""")

with open("CompletionManager.swift", "w") as f:
    f.write(content)
