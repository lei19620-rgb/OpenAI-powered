import Foundation

struct VocabularySessionScope {
    let coursewareID: UUID?
    let unitID: UUID?
}

/// Small, bounded batches keep a session finishable. Weak words get one extra
/// recall attempt after up to three other cards; further work stays scheduled.
enum VocabularySessionPlanner {
    static let batchSize = 20

    static func queueAfterRating(
        _ rating: VocabularyRating, itemID: UUID, queue: [UUID], index: Int,
        repeatedIDs: Set<UUID>
    ) -> [UUID] {
        guard rating == .notKnown || rating == .fuzzy,
              !repeatedIDs.contains(itemID), queue.indices.contains(index) else { return queue }
        var next = queue
        next.insert(itemID, at: min(index + 4, next.count))
        return next
    }
}
