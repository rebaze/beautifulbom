/// Back and forward through places, as in a browser.
public struct History<Place: Hashable & Sendable>: Sendable {
    private var backStack: [Place] = []
    private var forwardStack: [Place] = []
    public private(set) var current: Place?

    public init() {}

    /// Goes to `place`; visiting the current place again changes nothing.
    public mutating func visit(_ place: Place) {
        guard place != current else { return }
        if let current { backStack.append(current) }
        forwardStack.removeAll()
        current = place
    }

    public mutating func back() -> Place? {
        guard let p = backStack.popLast() else { return nil }
        if let current { forwardStack.append(current) }
        current = p
        return p
    }

    public mutating func forward() -> Place? {
        guard let p = forwardStack.popLast() else { return nil }
        if let current { backStack.append(current) }
        current = p
        return p
    }

    public var canGoBack: Bool { !backStack.isEmpty }
    public var canGoForward: Bool { !forwardStack.isEmpty }
}
