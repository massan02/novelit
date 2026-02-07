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

        let reduced = reduceHomeFlow(state: initial, action: .openEditor(fileName: "sample.md"))

        #expect(reduced.route == .editor(fileName: "sample.md"))
        #expect(reduced.activePanel == nil)
    }

    @Test("エディタで同じパネルを再タップすると閉じる")
    func tappingSamePanelTwiceClosesPanel() {
        let initial = HomeFlowState(route: .editor(fileName: "sample.md"), activePanel: .explorer)

        let reduced = reduceHomeFlow(state: initial, action: .togglePanel(.explorer))

        #expect(reduced.activePanel == nil)
    }

    @Test("エディタで別パネルをタップすると切り替わる")
    func tappingDifferentPanelSwitchesPanel() {
        let initial = HomeFlowState(route: .editor(fileName: "sample.md"), activePanel: .explorer)

        let reduced = reduceHomeFlow(state: initial, action: .togglePanel(.changes))

        #expect(reduced.activePanel == .changes)
    }

    @Test("エディタから履歴へ遷移すると編集中ファイル名を引き継ぎ、パネルは閉じる")
    func openHistoryMovesToHistoryKeepingFileName() {
        let initial = HomeFlowState(route: .editor(fileName: "sample.md"), activePanel: .graph)

        let reduced = reduceHomeFlow(state: initial, action: .openHistory)

        #expect(reduced.route == .history(fileName: "sample.md"))
        #expect(reduced.activePanel == nil)
    }

    @Test("履歴から戻るとエディタへ戻る")
    func backToEditorFromHistory() {
        let initial = HomeFlowState(route: .history(fileName: "sample.md"), activePanel: nil)

        let reduced = reduceHomeFlow(state: initial, action: .backToEditor)

        #expect(reduced.route == .editor(fileName: "sample.md"))
    }

    @Test("一覧画面でエディタ専用アクションを受けても状態は変わらない")
    func editorOnlyActionsAreIgnoredInList() {
        let initial = HomeFlowState(route: .list, activePanel: nil)

        let afterToggle = reduceHomeFlow(state: initial, action: .togglePanel(.explorer))
        let afterHistory = reduceHomeFlow(state: initial, action: .openHistory)

        #expect(afterToggle == initial)
        #expect(afterHistory == initial)
    }
}
