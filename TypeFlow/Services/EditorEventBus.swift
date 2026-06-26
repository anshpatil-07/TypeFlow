import Foundation
import Cocoa

enum EditorEventType {
    case textChanged(bufferSnapshot: String, isPunctuation: Bool)
    case documentContextChanged
    case spaceOrReturnPressed(bufferSnapshot: String)
    case selectionChanged
}

final class EditorEventBus: @unchecked Sendable {
    static let shared = EditorEventBus()
    
    private var observers: [(EditorEventType) -> Void] = []
    private let lock = NSLock()
    
    private init() {}
    
    func subscribe(_ observer: @escaping (EditorEventType) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        observers.append(observer)
    }
    
    func publish(_ event: EditorEventType) {
        lock.lock()
        let currentObservers = observers
        lock.unlock()
        
        // Dispatch to main queue if needed, but since it's an event bus, 
        // it's safer to let observers decide their threading.
        for observer in currentObservers {
            observer(event)
        }
    }
}
