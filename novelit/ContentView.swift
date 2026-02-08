//
//  ContentView.swift
//  novelit
//
//  Created by 村崎聖仁 on 2026/01/23.
//

import AuthenticationServices
import Combine
import SwiftUI
import SwiftData
#if canImport(UIKit)
import UIKit
#endif

protocol AppleSignInVerifying {
    func verify(appleUserId: String) async -> AppleSignInVerification
}

struct AppleIDCredentialStateVerifier: AppleSignInVerifying {
    func verify(appleUserId: String) async -> AppleSignInVerification {
        await withCheckedContinuation { continuation in
            ASAuthorizationAppleIDProvider().getCredentialState(forUserID: appleUserId) { credentialState, _ in
                switch credentialState {
                case .authorized:
                    continuation.resume(returning: .authorized)
                case .revoked, .notFound, .transferred:
                    continuation.resume(returning: .unauthorized)
                @unknown default:
                    continuation.resume(returning: .unauthorized)
                }
            }
        }
    }
}

enum AppleUserSessionAction: Equatable {
    case signInSucceeded(appleUserId: String)
    case signInFailed
    case signOut
}

struct AppleUserSessionState: Equatable {
    static let signInFailedMessage = "サインインに失敗しました"

    var storedAppleUserId: String
    var signInErrorMessage: String?
    var verificationRevision: Int = 0
}

func reduceAppleUserSession(
    state: AppleUserSessionState,
    action: AppleUserSessionAction
) -> AppleUserSessionState {
    switch action {
    case .signInSucceeded(let appleUserId):
        return AppleUserSessionState(
            storedAppleUserId: appleUserId,
            signInErrorMessage: nil,
            verificationRevision: state.verificationRevision + 1
        )
    case .signInFailed:
        return AppleUserSessionState(
            storedAppleUserId: state.storedAppleUserId,
            signInErrorMessage: AppleUserSessionState.signInFailedMessage,
            verificationRevision: state.verificationRevision
        )
    case .signOut:
        return AppleUserSessionState(
            storedAppleUserId: "",
            signInErrorMessage: nil,
            verificationRevision: state.verificationRevision
        )
    }
}

struct RootTaskID: Equatable, Hashable {
    let storedAppleUserId: String
    let verificationRevision: Int
}

func makeRootTaskID(storedAppleUserId: String, verificationRevision: Int) -> RootTaskID {
    RootTaskID(
        storedAppleUserId: storedAppleUserId,
        verificationRevision: verificationRevision
    )
}

@MainActor
final class RootViewModel: ObservableObject {
    nonisolated let objectWillChange = ObservableObjectPublisher()

    @Published private(set) var appleUserId: String?
    @Published private(set) var verification: AppleSignInVerification = .unknown

    private let verifier: AppleSignInVerifying
    private var verificationTask: Task<Void, Never>?

    init(verifier: AppleSignInVerifying) {
        self.verifier = verifier
    }

    var entryScreen: EntryScreen {
        decideEntryScreen(appleUserId: appleUserId, verification: verification)
    }

    func setAppleUserId(_ appleUserId: String?) {
        guard self.appleUserId != appleUserId else { return }

        self.appleUserId = appleUserId
        verificationTask?.cancel()

        guard let appleUserId else {
            verification = .unknown
            return
        }

        verification = .unknown
        verificationTask = Task { [weak self, verifier] in
            let result = await verifier.verify(appleUserId: appleUserId)
            guard let self, !Task.isCancelled else { return }
            self.verification = result
        }
    }
}

struct RootView: View {
    @AppStorage("appleUserId") private var storedAppleUserId: String = ""
    @AppStorage("appleUserIdVerificationRevision") private var verificationRevision: Int = 0
    @State private var homeSyncState: HomeSyncState = .localOnlyBanner
    @State private var isCheckingICloudStatus: Bool = false
    @State private var iCloudStatusRequestID: UInt64 = 0
    @StateObject private var viewModel: RootViewModel
    private let iCloudAccountStatusProvider: ICloudAccountStatusProviding

    init(
        verifier: AppleSignInVerifying = AppleIDCredentialStateVerifier(),
        iCloudAccountStatusProvider: ICloudAccountStatusProviding = CloudKitICloudAccountStatusProvider()
    ) {
        _viewModel = StateObject(wrappedValue: RootViewModel(verifier: verifier))
        self.iCloudAccountStatusProvider = iCloudAccountStatusProvider
    }

    var body: some View {
        Group {
            switch viewModel.entryScreen {
            case .signIn:
                SignInView(
                    storedAppleUserId: $storedAppleUserId,
                    verificationRevision: $verificationRevision
                )
            case .verifyingAppleSignIn:
                VerifyingAppleSignInView()
            case .home:
                switch decideHomeDestination(syncState: homeSyncState) {
                case .blockedByICloudSignIn:
                    ICloudSignInRequiredView(
                        onOpenSettings: openAppSettings,
                        onRetry: refreshHomeSyncState
                    )
                case .home:
                    ContentView(
                        storedAppleUserId: $storedAppleUserId,
                        syncStatusRowState: decideHomeSyncStatusRowState(
                            syncState: homeSyncState,
                            isCheckingICloudStatus: isCheckingICloudStatus
                        ),
                        onTapSettings: openAppSettings
                    )
                }
            }
        }
        .task(id: makeRootTaskID(
            storedAppleUserId: storedAppleUserId,
            verificationRevision: verificationRevision
        )) {
            let appleUserIdOrNil: String? = storedAppleUserId.isEmpty ? nil : storedAppleUserId
            await viewModel.setAppleUserId(appleUserIdOrNil)
        }
        .task(id: viewModel.entryScreen) {
            await refreshHomeSyncState()
        }
    }

    @MainActor
    private func refreshHomeSyncState() async {
        guard viewModel.entryScreen == .home else {
            iCloudStatusRequestID &+= 1
            homeSyncState = .localOnlyBanner
            isCheckingICloudStatus = false
            return
        }

        iCloudStatusRequestID &+= 1
        let requestID = iCloudStatusRequestID
        homeSyncState = .localOnlyBanner
        isCheckingICloudStatus = true
        let accountStatus = await iCloudAccountStatusProvider.currentStatus()
        guard requestID == iCloudStatusRequestID else {
            return
        }
        guard viewModel.entryScreen == .home else {
            isCheckingICloudStatus = false
            return
        }

        homeSyncState = decideHomeSyncState(accountStatus: accountStatus)
        isCheckingICloudStatus = false
    }
}

struct SignInView: View {
    @Binding var storedAppleUserId: String
    @Binding var verificationRevision: Int
    @State private var signInErrorMessage: String?

    #if DEBUG
    @State private var debugUserId: String = ""
    #endif

    var body: some View {
        VStack(spacing: 16) {
            Text("Sign In")
                .font(.title)

            SignInWithAppleButton(.signIn) { _ in
            } onCompletion: { result in
                switch result {
                case .success(let authorization):
                    guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                        apply(.signInFailed)
                        return
                    }
                    apply(.signInSucceeded(appleUserId: credential.user))
                case .failure:
                    apply(.signInFailed)
                }
            }
            .signInWithAppleButtonStyle(.black)
            .frame(height: 44)
            .padding(.horizontal)

            if let signInErrorMessage {
                Text(signInErrorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            #if DEBUG
            TextField("Debug Apple User ID", text: $debugUserId)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)

            Button("Debug: Save User ID") {
                apply(.signInSucceeded(appleUserId: debugUserId))
            }

            Button("Debug: Clear User ID") {
                apply(.signOut)
            }
            #endif
        }
        .padding()
    }

    private func apply(_ action: AppleUserSessionAction) {
        let reduced = reduceAppleUserSession(
            state: AppleUserSessionState(
                storedAppleUserId: storedAppleUserId,
                signInErrorMessage: signInErrorMessage,
                verificationRevision: verificationRevision
            ),
            action: action
        )
        storedAppleUserId = reduced.storedAppleUserId
        signInErrorMessage = reduced.signInErrorMessage
        verificationRevision = reduced.verificationRevision
    }
}

struct VerifyingAppleSignInView: View {
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Verifying Apple Sign-In…")
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

struct ContentView: View {
    @Binding var storedAppleUserId: String
    var syncStatusRowState: HomeSyncStatusRowState
    var onTapSettings: () -> Void

    @Query(sort: \Item.timestamp, order: .reverse) private var items: [Item]
    @Query(sort: \Work.updatedAt, order: .reverse) private var works: [Work]
    @State private var flowState = HomeFlowState()

    init(
        storedAppleUserId: Binding<String> = .constant(""),
        syncStatusRowState: HomeSyncStatusRowState = .hidden,
        onTapSettings: @escaping () -> Void = {}
    ) {
        _storedAppleUserId = storedAppleUserId
        self.syncStatusRowState = syncStatusRowState
        self.onTapSettings = onTapSettings
    }

    var body: some View {
        Group {
            switch flowState.route {
            case .list:
                listScreen
            case .editor(let workID, let fileName):
                EditorScreen(
                    fileName: fileName,
                    changes: makeChangeSummaries(workID: workID, fileName: fileName),
                    activePanel: flowState.activePanel,
                    onBackToList: { applyFlow(.backToList) },
                    onOpenHistory: { applyFlow(.openHistory) },
                    onTogglePanel: { panel in applyFlow(.togglePanel(panel)) },
                    onClosePanel: { applyFlow(.closePanel) },
                    onOpenEditor: { targetFileName in
                        applyFlow(.openEditor(workID: workID, fileName: targetFileName))
                    }
                )
            case .history(_, let fileName):
                HistoryScreen(
                    fileName: fileName,
                    onBackToEditor: { applyFlow(.backToEditor) }
                )
            }
        }
    }

    private var listScreen: some View {
        NavigationStack {
            List {
                if syncStatusRowState != .hidden {
                    HomeSyncStatusRow(state: syncStatusRowState, onTapSettings: onTapSettings)
                        .listRowSeparator(.hidden)
                }

                ForEach(documentRows) { row in
                    Button {
                        applyFlow(.openEditor(workID: row.workID, fileName: row.title))
                    } label: {
                        DocumentRow(row: row)
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle("作品一覧")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: onTapSettings) {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("設定")
                }
            }
        }
    }

    private var documentRows: [DocumentRowData] {
        if !works.isEmpty {
            return works.map { work in
                DocumentRowData(
                    id: work.id.uuidString,
                    workID: work.id,
                    title: work.title,
                    updatedAt: work.updatedAt,
                    kindLabel: "小説"
                )
            }
        }

        if items.isEmpty {
            return [
                DocumentRowData(
                    id: "sample-document",
                    workID: nil,
                    title: "サンプル作品",
                    updatedAt: Date(),
                    kindLabel: "小説"
                )
            ]
        }

        return items.enumerated().map { index, item in
            DocumentRowData(
                id: "\(index)-\(item.timestamp.timeIntervalSince1970)",
                workID: nil,
                title: "作品\(index + 1)",
                updatedAt: item.timestamp,
                kindLabel: "小説"
            )
        }
    }

    private func makeChangeSummaries(workID: UUID?, fileName: String) -> [FileChangeSummary] {
        let targetWork: Work?
        if let workID {
            targetWork = works.first(where: { $0.id == workID })
        } else {
            targetWork = works.first(where: { $0.title == fileName })
        }

        guard let targetWork else {
            return [
                makeFileChangeSummary(
                    fileName: fileName,
                    previousText: "",
                    currentText: ""
                )
            ]
        }

        let summaries = targetWork.nodes
            .filter { $0.kind == .file }
            .compactMap { node -> FileChangeSummary? in
                guard let document = node.document else {
                    return nil
                }

                // TODO: Snapshot.manifestJSON から過去テキストを取得して比較する。
                let previousText = ""
                return makeFileChangeSummary(
                    fileName: "\(node.name).md",
                    previousText: previousText,
                    currentText: document.text
                )
            }
            .sorted { $0.fileName < $1.fileName }

        if summaries.isEmpty {
            return [
                makeFileChangeSummary(
                    fileName: fileName,
                    previousText: "",
                    currentText: ""
                )
            ]
        }
        return summaries
    }

    private func makeFileChangeSummary(
        fileName: String,
        previousText: String,
        currentText: String
    ) -> FileChangeSummary {
        let diffLines = buildUnifiedDiffLines(previousText: previousText, currentText: currentText)
        let addedLineCount = diffLines.filter { $0.kind == .added }.count
        let removedLineCount = diffLines.filter { $0.kind == .removed }.count

        return FileChangeSummary(
            fileName: fileName,
            addedLineCount: addedLineCount,
            removedLineCount: removedLineCount,
            diffLines: diffLines
        )
    }

    private func buildUnifiedDiffLines(previousText: String, currentText: String) -> [UnifiedDiffLine] {
        let previousLines = splitLines(previousText)
        let currentLines = splitLines(currentText)

        if previousLines.isEmpty && currentLines.isEmpty {
            return [UnifiedDiffLine(kind: .unchanged, text: "変更なし")]
        }

        let m = previousLines.count
        let n = currentLines.count
        var lcs = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)

        if m > 0, n > 0 {
            for i in stride(from: m - 1, through: 0, by: -1) {
                for j in stride(from: n - 1, through: 0, by: -1) {
                    if previousLines[i] == currentLines[j] {
                        lcs[i][j] = lcs[i + 1][j + 1] + 1
                    } else {
                        lcs[i][j] = max(lcs[i + 1][j], lcs[i][j + 1])
                    }
                }
            }
        }

        var i = 0
        var j = 0
        var result: [UnifiedDiffLine] = []

        while i < m && j < n {
            if previousLines[i] == currentLines[j] {
                result.append(UnifiedDiffLine(kind: .unchanged, text: previousLines[i]))
                i += 1
                j += 1
            } else if lcs[i + 1][j] >= lcs[i][j + 1] {
                result.append(UnifiedDiffLine(kind: .removed, text: previousLines[i]))
                i += 1
            } else {
                result.append(UnifiedDiffLine(kind: .added, text: currentLines[j]))
                j += 1
            }
        }

        while i < m {
            result.append(UnifiedDiffLine(kind: .removed, text: previousLines[i]))
            i += 1
        }

        while j < n {
            result.append(UnifiedDiffLine(kind: .added, text: currentLines[j]))
            j += 1
        }

        return result
    }

    private func splitLines(_ text: String) -> [String] {
        guard !text.isEmpty else {
            return []
        }
        return text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }

    private func applyFlow(_ action: HomeFlowAction) {
        flowState = reduceHomeFlow(state: flowState, action: action)
    }
}

private struct DocumentRowData: Identifiable, Equatable {
    let id: String
    let workID: UUID?
    let title: String
    let updatedAt: Date
    let kindLabel: String
}

private struct DocumentRow: View {
    let row: DocumentRowData

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(row.title)
                    .font(.headline)
                    .lineLimit(1)

                Text(row.updatedAt, format: Date.FormatStyle(date: .numeric, time: .shortened))
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Text(row.kindLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.footnote)
                .foregroundStyle(.tertiary)
                .padding(.top, 4)
        }
    }
}

private struct EditorScreen: View {
    let fileName: String
    let changes: [FileChangeSummary]
    let activePanel: EditorPanel?
    let onBackToList: () -> Void
    let onOpenHistory: () -> Void
    let onTogglePanel: (EditorPanel) -> Void
    let onClosePanel: () -> Void
    let onOpenEditor: (String) -> Void

    private var activePanelBinding: Binding<EditorPanel?> {
        Binding(
            get: { activePanel },
            set: { nextValue in
                if nextValue == nil {
                    onClosePanel()
                }
            }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button(action: onBackToList) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("戻る")
                    }
                }

                Text(fileName)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer()

                Button("履歴", action: onOpenHistory)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                Text("エディタ本文（プレースホルダ）")
                    .font(.body)
                    .foregroundStyle(.secondary)

                Text("MVP-6: 一覧 -> エディタ -> 履歴の導線を実装")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(16)

            Divider()

            HStack(spacing: 12) {
                HStack(spacing: 8) {
                    panelButton(.explorer)
                    panelButton(.branch)
                    panelButton(.graph)
                }

                Spacer()

                Button(action: { onTogglePanel(.changes) }) {
                    Text(EditorPanel.changes.displayTitle)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .sheet(item: activePanelBinding) { panel in
            if panel == .changes {
                ChangesPanelSheet(
                    files: changes,
                    onClose: onClosePanel,
                    onOpenEditor: onOpenEditor
                )
            } else {
                PanelPlaceholderSheet(
                    panel: panel,
                    onClose: onClosePanel
                )
            }
        }
    }

    private func panelButton(_ panel: EditorPanel) -> some View {
        let isSelected = activePanel == panel

        return Button(action: { onTogglePanel(panel) }) {
            Text(panel.displayTitle)
                .font(.footnote)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
        )
    }
}

private struct ChangesPanelSheet: View {
    let onClose: () -> Void
    let onOpenEditor: (String) -> Void

    @State private var panelState: ChangesPanelState

    init(
        files: [FileChangeSummary],
        onClose: @escaping () -> Void,
        onOpenEditor: @escaping (String) -> Void
    ) {
        self.onClose = onClose
        self.onOpenEditor = onOpenEditor
        _panelState = State(initialValue: ChangesPanelState(files: files))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let diffFile = panelState.diffFile {
                    diffContent(for: diffFile)
                } else {
                    listContent
                }
            }
            .navigationTitle(EditorPanel.changes.displayTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if panelState.diffFile != nil {
                        Button("戻る") {
                            panelState = reduceChangesPanel(state: panelState, action: .closeDiff)
                        }
                    } else {
                        Button("閉じる", action: onClose)
                    }
                }
            }
        }
    }

    private var listContent: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                Spacer()

                Button("すべて選択") {
                    panelState = reduceChangesPanel(state: panelState, action: .selectAll)
                }
                .font(.footnote)

                Button("すべて解除") {
                    panelState = reduceChangesPanel(state: panelState, action: .clearAll)
                }
                .font(.footnote)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            ScrollView {
                if panelState.files.isEmpty {
                    Text("変更はありません")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 24)
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(panelState.files) { file in
                            HStack(spacing: 10) {
                                Button {
                                    panelState = reduceChangesPanel(
                                        state: panelState,
                                        action: .toggleFileSelection(fileName: file.fileName)
                                    )
                                } label: {
                                    Image(systemName: panelState.selectedFileNames.contains(file.fileName) ? "checkmark.square.fill" : "square")
                                        .foregroundStyle(panelState.selectedFileNames.contains(file.fileName) ? Color.accentColor : Color.secondary)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("\(file.fileName) を選択")

                                Text(file.fileName)
                                    .font(.body)
                                    .lineLimit(1)
                                    .truncationMode(.middle)

                                Spacer(minLength: 8)

                                Text(file.changeLabel)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                Button {
                                    panelState = reduceChangesPanel(
                                        state: panelState,
                                        action: .openDiff(fileName: file.fileName)
                                    )
                                } label: {
                                    Image(systemName: "chevron.right")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("\(file.fileName) の差分を表示")
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)

                            Divider()
                        }
                    }
                }
            }

            Button("保存") {
            }
            .buttonStyle(.borderedProminent)
            .disabled(!panelState.canSaveSelection)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(16)
        }
    }

    private func diffContent(for file: FileChangeSummary) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(file.fileName)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(file.diffLines.enumerated()), id: \.offset) { _, line in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(line.kind.symbol)
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(color(for: line.kind))

                            Text(line.text.isEmpty ? " " : line.text)
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(color(for: line.kind))

                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 1)
                    }
                }
                .padding(.vertical, 8)
            }

            Divider()

            Button("このファイルを開く") {
                onOpenEditor(file.fileName)
                onClose()
            }
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(16)
        }
    }

    private func color(for kind: UnifiedDiffLineKind) -> Color {
        switch kind {
        case .added:
            return .green
        case .removed:
            return .red
        case .unchanged:
            return .primary
        }
    }
}

private struct PanelPlaceholderSheet: View {
    let panel: EditorPanel
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Text("\(panel.displayTitle) パネル")
                    .font(.title3)
                    .fontWeight(.semibold)

                Text("プレースホルダ")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
            .navigationTitle(panel.displayTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("閉じる", action: onClose)
                }
            }
        }
    }
}

private struct HistoryScreen: View {
    let fileName: String
    let onBackToEditor: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button(action: onBackToEditor) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("戻る")
                    }
                }

                Text("履歴")
                    .font(.headline)

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                Text(fileName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text("履歴ビュー（プレースホルダ）")
                    .font(.body)
                    .fontWeight(.semibold)

                Text("・初期版\n・下書き保存")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(16)
        }
    }
}

struct ICloudSignInRequiredView: View {
    let onOpenSettings: () -> Void
    let onRetry: () async -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "icloud.slash")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)

            Text("iCloudへのサインインが必要です")
                .font(.title3)
                .fontWeight(.semibold)

            Text("iCloudにサインインすると同期機能を利用できます。")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            Button("設定を開く", action: onOpenSettings)
                .buttonStyle(.borderedProminent)

            Button("再確認") {
                Task { await onRetry() }
            }
            .buttonStyle(.bordered)
        }
        .padding()
    }
}

struct HomeSyncStatusRow: View {
    let state: HomeSyncStatusRowState
    let onTapSettings: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            switch state {
            case .checkingLocalOnly:
                ProgressView()
                    .controlSize(.small)

                Text("iCloud同期を確認中（ローカル保存のみ）")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

            case .localOnly:
                Image(systemName: "icloud.slash")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Text("同期は現在利用できません（ローカル保存のみ）")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer(minLength: 8)

                Button("設定", action: onTapSettings)
                    .font(.footnote)

            case .hidden:
                EmptyView()
            }
        }
        .padding(.vertical, 4)
    }
}

private func openAppSettings() {
#if canImport(UIKit)
    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
    UIApplication.shared.open(url)
#endif
}

#Preview {
    ContentView()
        .modelContainer(for: [Item.self, Work.self, Node.self, Document.self, Snapshot.self], inMemory: true)
}
