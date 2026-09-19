import Foundation

/// A result belongs to both its submitted conditions and its particular request.
struct ClassroomLookupPresentationState {
    private var queryKey: ClassroomLookupQueryKey?
    private var activeRequestID: UUID?
    private var result: ClassroomLookupOutcome?

    var isLoading: Bool { activeRequestID != nil }

    @discardableResult
    mutating func updateQuery(to key: ClassroomLookupQueryKey) -> Bool {
        guard queryKey != key else { return false }
        invalidate()
        queryKey = key
        return true
    }

    mutating func invalidate() {
        queryKey = nil
        activeRequestID = nil
        result = nil
    }

    mutating func begin(_ request: ClassroomLookupRequest) {
        updateQuery(to: request.queryKey)
        activeRequestID = request.id
        result = nil
    }

    func isCurrent(_ request: ClassroomLookupRequest, matching currentKey: ClassroomLookupQueryKey) -> Bool {
        activeRequestID == request.id && queryKey == request.queryKey && queryKey == currentKey
    }

    @discardableResult
    mutating func accept(
        _ outcome: ClassroomLookupOutcome,
        for request: ClassroomLookupRequest,
        matching currentKey: ClassroomLookupQueryKey
    ) -> Bool {
        guard isCurrent(request, matching: currentKey) else { return false }
        result = outcome
        return true
    }

    mutating func finish(_ request: ClassroomLookupRequest) {
        guard activeRequestID == request.id else { return }
        activeRequestID = nil
    }

    func outcome(for key: ClassroomLookupQueryKey) -> ClassroomLookupOutcome? {
        queryKey == key ? result : nil
    }
}
