import Foundation

enum HomeFlowRoute: Equatable {
    case list
    case editor(workID: UUID?, fileName: String)
    case history(workID: UUID?, fileName: String)
}

enum UnifiedDiffLineKind: Equatable {
    case added
    case removed
    case unchanged

    var symbol: String {
        switch self {
        case .added:
            return "+"
        case .removed:
            return "-"
        case .unchanged:
            return " "
        }
    }
}

struct UnifiedDiffLine: Equatable {
    let kind: UnifiedDiffLineKind
    let text: String
}

struct FileChangeSummary: Equatable, Identifiable {
    let fileName: String
    let addedLineCount: Int
    let removedLineCount: Int
    let diffLines: [UnifiedDiffLine]

    var id: String {
        fileName
    }

    var changeLabel: String {
        "+\(addedLineCount)/-\(removedLineCount)"
    }
}

struct ChangesPanelState: Equatable {
    var files: [FileChangeSummary]
    var selectedFileNames: Set<String>
    var diffFileName: String?

    private static func hasRealChange(_ file: FileChangeSummary) -> Bool {
        file.addedLineCount > 0 || file.removedLineCount > 0
    }

    var selectableFileNames: Set<String> {
        Set(files.filter(Self.hasRealChange).map(\.fileName))
    }

    init(
        files: [FileChangeSummary],
        selectedFileNames: Set<String>? = nil,
        diffFileName: String? = nil
    ) {
        let changedFiles = files.filter(Self.hasRealChange)
        self.files = changedFiles
        let defaultSelection = Set(changedFiles.map(\.fileName))
        self.selectedFileNames = selectedFileNames?.intersection(defaultSelection) ?? defaultSelection
        self.diffFileName = diffFileName
    }

    var canSaveSelection: Bool {
        !selectedFileNames.intersection(selectableFileNames).isEmpty
    }

    var diffFile: FileChangeSummary? {
        guard let diffFileName else {
            return nil
        }
        return files.first { $0.fileName == diffFileName }
    }
}

enum ChangesPanelAction: Equatable {
    case selectAll
    case clearAll
    case toggleFileSelection(fileName: String)
    case openDiff(fileName: String)
    case closeDiff
}

func reduceChangesPanel(state: ChangesPanelState, action: ChangesPanelAction) -> ChangesPanelState {
    var next = state

    switch action {
    case .selectAll:
        next.selectedFileNames = next.selectableFileNames
        return next

    case .clearAll:
        next.selectedFileNames = []
        return next

    case .toggleFileSelection(let fileName):
        guard next.selectableFileNames.contains(fileName) else {
            return next
        }

        if next.selectedFileNames.contains(fileName) {
            next.selectedFileNames.remove(fileName)
        } else {
            next.selectedFileNames.insert(fileName)
        }
        return next

    case .openDiff(let fileName):
        guard next.files.contains(where: { $0.fileName == fileName }) else {
            return next
        }
        next.diffFileName = fileName
        return next

    case .closeDiff:
        next.diffFileName = nil
        return next
    }
}

enum EditorPanel: String, Equatable, CaseIterable, Identifiable {
    case explorer
    case branch
    case graph
    case changes

    var id: String {
        rawValue
    }

    var displayTitle: String {
        switch self {
        case .explorer:
            return "Explorer"
        case .branch:
            return "Branch"
        case .graph:
            return "Graph"
        case .changes:
            return "Changes"
        }
    }
}

struct HomeFlowState: Equatable {
    var route: HomeFlowRoute = .list
    var activePanel: EditorPanel? = nil
}

enum HomeFlowAction: Equatable {
    case openEditor(workID: UUID?, fileName: String)
    case backToList
    case openHistory
    case backToEditor
    case togglePanel(EditorPanel)
    case closePanel
}

func reduceHomeFlow(state: HomeFlowState, action: HomeFlowAction) -> HomeFlowState {
    switch action {
    case .openEditor(let workID, let fileName):
        return HomeFlowState(route: .editor(workID: workID, fileName: fileName), activePanel: nil)

    case .backToList:
        return HomeFlowState(route: .list, activePanel: nil)

    case .openHistory:
        guard case let .editor(workID, fileName) = state.route else {
            return state
        }
        return HomeFlowState(route: .history(workID: workID, fileName: fileName), activePanel: nil)

    case .backToEditor:
        guard case let .history(workID, fileName) = state.route else {
            return state
        }
        return HomeFlowState(route: .editor(workID: workID, fileName: fileName), activePanel: nil)

    case .togglePanel(let panel):
        guard case .editor = state.route else {
            return state
        }

        let nextPanel: EditorPanel? = state.activePanel == panel ? nil : panel
        return HomeFlowState(route: state.route, activePanel: nextPanel)

    case .closePanel:
        guard state.activePanel != nil else {
            return state
        }
        return HomeFlowState(route: state.route, activePanel: nil)
    }
}
