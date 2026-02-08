import Foundation
import Testing
@testable import novelit

struct HomeFlowReducerTests {
    @Test("初期状態は一覧表示でパネル未選択")
    func initialStateIsListWithNoPanel() {
        let state = HomeFlowState()

        #expect(state.route == .list)
        #expect(state.activePanel == nil)
    }

    @Test("一覧からファイルを開くとエディタへ遷移し、パネルは閉じる")
    func openEditorMovesToEditorAndClearsPanel() {
        let initial = HomeFlowState(route: .list, activePanel: .graph)
        let workID = UUID()

        let reduced = reduceHomeFlow(state: initial, action: .openEditor(workID: workID, fileName: "sample.md"))

        #expect(reduced.route == .editor(workID: workID, fileName: "sample.md"))
        #expect(reduced.activePanel == nil)
    }

    @Test("エディタで同じパネルを再タップすると閉じる")
    func tappingSamePanelTwiceClosesPanel() {
        let initial = HomeFlowState(route: .editor(workID: nil, fileName: "sample.md"), activePanel: .explorer)

        let reduced = reduceHomeFlow(state: initial, action: .togglePanel(.explorer))

        #expect(reduced.activePanel == nil)
    }

    @Test("エディタで別パネルをタップすると切り替わる")
    func tappingDifferentPanelSwitchesPanel() {
        let initial = HomeFlowState(route: .editor(workID: nil, fileName: "sample.md"), activePanel: .explorer)

        let reduced = reduceHomeFlow(state: initial, action: .togglePanel(.changes))

        #expect(reduced.activePanel == .changes)
    }

    @Test("エディタでBranchパネルも開閉できる")
    func branchPanelCanBeOpenedAndClosed() {
        let initial = HomeFlowState(route: .editor(workID: nil, fileName: "sample.md"), activePanel: nil)

        let opened = reduceHomeFlow(state: initial, action: .togglePanel(.branch))
        let closed = reduceHomeFlow(state: opened, action: .togglePanel(.branch))

        #expect(opened.activePanel == .branch)
        #expect(closed.activePanel == nil)
    }

    @Test("エディタから履歴へ遷移すると編集中ファイル名を引き継ぎ、パネルは閉じる")
    func openHistoryMovesToHistoryKeepingFileName() {
        let workID = UUID()
        let initial = HomeFlowState(route: .editor(workID: workID, fileName: "sample.md"), activePanel: .graph)

        let reduced = reduceHomeFlow(state: initial, action: .openHistory)

        #expect(reduced.route == .history(workID: workID, fileName: "sample.md"))
        #expect(reduced.activePanel == nil)
    }

    @Test("履歴から戻るとエディタへ戻る")
    func backToEditorFromHistory() {
        let workID = UUID()
        let initial = HomeFlowState(route: .history(workID: workID, fileName: "sample.md"), activePanel: nil)

        let reduced = reduceHomeFlow(state: initial, action: .backToEditor)

        #expect(reduced.route == .editor(workID: workID, fileName: "sample.md"))
    }

    @Test("Changes経路でファイル名が変わっても同じWork IDを維持する")
    func openEditorFromChangesKeepsWorkIDContext() {
        let workID = UUID()
        let initial = HomeFlowState(route: .editor(workID: workID, fileName: "作品A"), activePanel: .changes)

        let reduced = reduceHomeFlow(
            state: initial,
            action: .openEditor(workID: workID, fileName: "content.md")
        )

        #expect(reduced.route == .editor(workID: workID, fileName: "content.md"))
        #expect(reduced.activePanel == nil)
    }

    @Test("同名タイトルでも渡されたWork IDを優先してエディタ遷移先を識別する")
    func openEditorUsesWorkIDForDuplicateTitles() {
        let duplicatedTitle = "同名作品"
        let firstID = UUID()
        let secondID = UUID()

        let first = reduceHomeFlow(
            state: HomeFlowState(),
            action: .openEditor(workID: firstID, fileName: duplicatedTitle)
        )
        let second = reduceHomeFlow(
            state: HomeFlowState(),
            action: .openEditor(workID: secondID, fileName: duplicatedTitle)
        )

        #expect(first.route == .editor(workID: firstID, fileName: duplicatedTitle))
        #expect(second.route == .editor(workID: secondID, fileName: duplicatedTitle))
        #expect(first.route != second.route)
    }

    @Test("一覧画面でエディタ専用アクションを受けても状態は変わらない")
    func editorOnlyActionsAreIgnoredInList() {
        let initial = HomeFlowState(route: .list, activePanel: nil)

        let afterToggle = reduceHomeFlow(state: initial, action: .togglePanel(.explorer))
        let afterHistory = reduceHomeFlow(state: initial, action: .openHistory)

        #expect(afterToggle == initial)
        #expect(afterHistory == initial)
    }

    @Test("Changesパネルで全選択と全解除を切り替えられる")
    func changesPanelSelectAllAndClearAll() {
        let files = [
            FileChangeSummary(fileName: "content.md", addedLineCount: 1, removedLineCount: 0, diffLines: []),
            FileChangeSummary(fileName: "outline.md", addedLineCount: 2, removedLineCount: 1, diffLines: [])
        ]
        let initial = ChangesPanelState(files: files, selectedFileNames: [])

        let selected = reduceChangesPanel(state: initial, action: .selectAll)
        let cleared = reduceChangesPanel(state: selected, action: .clearAll)

        #expect(selected.selectedFileNames == Set(["content.md", "outline.md"]))
        #expect(cleared.selectedFileNames.isEmpty)
    }

    @Test("Changesパネルは選択0件のとき保存不可になる")
    func changesPanelSaveDisabledWhenNoSelection() {
        let files = [
            FileChangeSummary(fileName: "content.md", addedLineCount: 1, removedLineCount: 0, diffLines: [])
        ]
        let initial = ChangesPanelState(files: files, selectedFileNames: [])

        #expect(initial.canSaveSelection == false)

        let selected = reduceChangesPanel(state: initial, action: .selectAll)
        #expect(selected.canSaveSelection)
    }

    @Test("変更0件のファイルは一覧対象外になり保存対象にもならない")
    func unchangedFilesAreExcludedFromChangesPanel() {
        let files = [
            FileChangeSummary(fileName: "content.md", addedLineCount: 0, removedLineCount: 0, diffLines: []),
            FileChangeSummary(fileName: "outline.md", addedLineCount: 2, removedLineCount: 1, diffLines: [])
        ]
        let state = ChangesPanelState(files: files)

        #expect(state.files.map(\.fileName) == ["outline.md"])
        #expect(state.selectedFileNames == Set(["outline.md"]))
        #expect(state.canSaveSelection)
    }

    @Test("Changes一覧の右矢印操作で差分表示対象へ遷移する")
    func changesPanelOpenDiffMovesToDiffState() {
        let files = [
            FileChangeSummary(fileName: "content.md", addedLineCount: 1, removedLineCount: 0, diffLines: []),
            FileChangeSummary(fileName: "plot.md", addedLineCount: 0, removedLineCount: 1, diffLines: [])
        ]
        let initial = ChangesPanelState(files: files)

        let reduced = reduceChangesPanel(state: initial, action: .openDiff(fileName: "plot.md"))

        #expect(reduced.diffFileName == "plot.md")
        #expect(reduced.diffFile?.fileName == "plot.md")
    }
}
