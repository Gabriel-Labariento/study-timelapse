import Foundation

public enum SessionState: String {
    case idle, preparing, recording, paused, finishing, error
    public var acceptsSamples: Bool { self == .recording }
    public var isBusy: Bool { [.preparing, .recording, .paused, .finishing].contains(self) }
    @discardableResult public mutating func transition(to next: SessionState) -> Bool {
        let allowed: Bool
        switch (self, next) {
        case (.idle, .preparing), (.error, .preparing), (.error, .idle),
             (.preparing, .recording), (.preparing, .finishing), (.preparing, .error),
             (.recording, .paused), (.recording, .finishing),
             (.paused, .recording), (.paused, .finishing),
             (.finishing, .idle), (.finishing, .error): allowed = true
        default: allowed = false
        }
        if allowed { self = next }
        return allowed
    }
}
public enum SaveDecision: Equatable {
    case start(replaceExisting: Bool), confirmReplacement, cancel
}
public enum DestinationPolicy {
    public static func saveDecision(existsNow: Bool, confirmation: Bool?) -> SaveDecision {
        guard existsNow else { return .start(replaceExisting: false) }
        guard let confirmation else { return .confirmReplacement }
        return confirmation ? .start(replaceExisting: true) : .cancel
    }
    public static func canPublish(existsNow: Bool, replacementApproved: Bool) -> Bool {
        !existsNow || replacementApproved
    }
}
