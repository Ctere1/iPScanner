import Foundation

/// Runs `operation` over `items` with at most `limit` of them in flight, handing each result to
/// `onEach` as it lands.
///
/// The scan pipeline is a series of "probe N things at once, but never all 65k of them" loops, and
/// each one had hand-rolled the same priming-then-refilling iterator dance around `withTaskGroup`.
/// Six copies drifted: one of them never checked for cancellation at all, so a cancelled port scan
/// kept probing to completion.
///
/// Return `false` from `onEach` to stop early — remaining items are never started, and in-flight
/// work is cancelled.
func withWindowedTaskGroup<Item: Sendable, Output: Sendable>(
    over items: [Item],
    limit: Int,
    operation: @escaping @Sendable (Item) async -> Output,
    onEach: (Output) async -> Bool
) async {
    guard !items.isEmpty, limit > 0 else { return }

    await withTaskGroup(of: Output.self) { group in
        var iter = items.makeIterator()

        for _ in 0..<min(limit, items.count) {
            guard let item = iter.next() else { break }
            group.addTask { await operation(item) }
        }

        while let output = await group.next() {
            let shouldContinue = await onEach(output)
            // Task.isCancelled covers the caller's task being torn down; `shouldContinue` covers a
            // caller that decided on its own to stop (a superseded scan generation, say).
            if !shouldContinue || Task.isCancelled {
                group.cancelAll()
                break
            }
            if let next = iter.next() {
                group.addTask { await operation(next) }
            }
        }
    }
}

/// Collecting form of ``withWindowedTaskGroup(over:limit:operation:onEach:)``, for callers that
/// want every result rather than a running fold.
///
/// Results come back in completion order, not `items` order — every current caller either sorts
/// afterwards or does not care.
func windowedMap<Item: Sendable, Output: Sendable>(
    _ items: [Item],
    limit: Int,
    _ operation: @escaping @Sendable (Item) async -> Output
) async -> [Output] {
    var results: [Output] = []
    results.reserveCapacity(items.count)
    await withWindowedTaskGroup(over: items, limit: limit, operation: operation) { output in
        results.append(output)
        return true
    }
    return results
}
