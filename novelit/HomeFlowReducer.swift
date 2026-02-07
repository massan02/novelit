import Foundation

enum HomeFlowRoute: Equatable {
    case list
    case editor(fileName: String)
    case history(fileName: String)
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
    case openEditor(fileName: String)
    case backToList
    case openHistory
    case backToEditor
    case togglePanel(EditorPanel)
    case closePanel
}

func reduceHomeFlow(state: HomeFlowState, action: HomeFlowAction) -> HomeFlowState {
    switch action {
    case .openEditor(let fileName):
        return HomeFlowState(route: .editor(fileName: fileName), activePanel: nil)

    case .backToList:
        return HomeFlowState(route: .list, activePanel: nil)

    case .openHistory:
        guard case let .editor(fileName) = state.route else {
            return state
        }
        return HomeFlowState(route: .history(fileName: fileName), activePanel: nil)

    case .backToEditor:
        guard case let .history(fileName) = state.route else {
            return state
        }
        return HomeFlowState(route: .editor(fileName: fileName), activePanel: nil)

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
