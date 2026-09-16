import Foundation

@MainActor
final class AppRouter: ObservableObject {
    @Published var selectedTab: RootTab = .today
    @Published var requestedTodoID: UUID?
    @Published var studyHomeRequest = 0
    @Published var requestedWorkspaceID: UUID?
    @Published var requestedHomeworkID: UUID?
    @Published var requestedVocabularyCoursewareID: UUID?
    @Published var requestedVocabularyUnitID: UUID?
    @Published var vocabularyRequest = 0
    @Published var homeworkLibraryRequest = 0

    init() {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "-SimpleStudyInitialTab"),
           arguments.indices.contains(index + 1) {
            selectedTab = switch arguments[index + 1] {
            case "study": .study
            case "vocabulary": .vocabulary
            case "my": .my
            default: .today
            }
        }
        #endif
    }

    func openStudy(workspaceID: UUID? = nil) {
        requestedWorkspaceID = workspaceID
        if workspaceID == nil { studyHomeRequest += 1 }
        selectedTab = .study
    }

    func openHomework(homeworkID: UUID? = nil) {
        if let homeworkID {
            requestedHomeworkID = homeworkID
        } else {
            homeworkLibraryRequest += 1
        }
        selectedTab = .study
    }

    func openVocabulary(coursewareID: UUID? = nil, unitID: UUID? = nil) {
        requestedVocabularyCoursewareID = coursewareID
        requestedVocabularyUnitID = unitID
        vocabularyRequest += 1
        selectedTab = .vocabulary
    }
}
