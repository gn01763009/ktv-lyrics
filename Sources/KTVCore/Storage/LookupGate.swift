/// Tags lookups with a generation number so that results from an older lookup can be ignored.
/// Each `next()` gate supersedes the previous one.
public struct LookupGate: Equatable, Sendable {
    public let currentID: Int

    public init() {
        self.init(currentID: 0)
    }

    private init(currentID: Int) {
        self.currentID = currentID
    }

    /// The gate that supersedes this one.
    public func next() -> LookupGate {
        LookupGate(currentID: currentID + 1)
    }

    /// True only for the ID of the current generation.
    public func accepts(_ id: Int) -> Bool {
        id == currentID
    }
}
