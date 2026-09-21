import Foundation
import SwiftData

/// Resolves saved learning evidence independently of time/dependency gates.
/// Reading evidence never performs actions, requests permissions, or navigates.
@MainActor
enum LearningCompletionService {
    static func accepts(_ date: Date?, for todo: TodoRecord) -> Bool {
        guard let date else { return false }
        guard todo.recurrence != .none else { return true }
        // Repeating work must belong to this occurrence. Early study on the
        // scheduled day counts, but yesterday's result must not count again.
        let start = max(todo.createdAt, Calendar.current.startOfDay(for: todo.originalScheduledAt))
        return date >= start
    }

    static func hasEvidence(for todo: TodoRecord, context: ModelContext) throws -> Bool {
        switch todo.completionRule {
        case .manual:
            return false
        case .lessonCompletion:
            guard let id = todo.workspaceID else { return false }
            return try context.fetch(FetchDescriptor<StudyWorkspaceRecord>()).contains {
                $0.id == id && $0.isCompleted && accepts($0.completedAt, for: todo)
            }
        case .homeworkSubmission:
            let definitions = try context.fetch(FetchDescriptor<HomeworkDefinitionRecord>())
            let ids = Set(definitions.filter {
                if let id = todo.homeworkID { return $0.id == id }
                return todo.workspaceID != nil && $0.workspaceID == todo.workspaceID
            }.map(\.id))
            return try context.fetch(FetchDescriptor<HomeworkAttemptRecord>()).contains {
                ids.contains($0.homeworkID) && $0.state == .submitted && accepts($0.submittedAt, for: todo)
            }
        case .vocabularyUnitCompletion:
            return try context.fetch(FetchDescriptor<VocabularyUnitRecord>()).contains {
                $0.id == todo.vocabularyUnitID && $0.coursewareID == todo.vocabularyCoursewareID &&
                    $0.isActive && accepts($0.completedAt, for: todo)
            }
        case .vocabularyCoursewareCompletion:
            return try context.fetch(FetchDescriptor<VocabularyCoursewareRecord>()).contains {
                $0.id == todo.vocabularyCoursewareID && accepts($0.completedAt, for: todo)
            }
        case .vocabularyReviewSession:
            return accepts(todo.learningEvidenceAt, for: todo)
        }
    }

    /// Called only for a nonempty, finished review session, in the same save as
    /// the final rating. Exact scope prevents an unrelated/global batch from
    /// accidentally completing a specific unit's task.
    static func recordVocabularySession(
        coursewareID: UUID?, unitID: UUID?, at date: Date, context: ModelContext
    ) throws {
        for todo in try context.fetch(FetchDescriptor<TodoRecord>()) where
            todo.storedState != .completed && todo.storedState != .cancelled &&
            todo.completionRule == .vocabularyReviewSession &&
            todo.vocabularyCoursewareID == coursewareID && todo.vocabularyUnitID == unitID &&
            accepts(date, for: todo) {
            todo.learningEvidenceAt = date
        }
    }
}
