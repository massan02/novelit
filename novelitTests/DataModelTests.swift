import Foundation
import SwiftData
import Testing
@testable import novelit

struct DataModelTests {
    @Test("標準テンプレートで初期ノード構成を生成する")
    func standardTemplateCreatesInitialStructure() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let work = WorkFactory.create(title: "新規作品", template: .standard, now: now)

        let expected = Set(["content", "outline", "plot", "characters", "info", "snapshots"])
        let actual = Set(work.rootNodes.map(\Node.name))

        #expect(actual == expected)
        #expect(work.document(kind: .content) != nil)
        #expect(work.document(kind: .outline) != nil)
        #expect(work.document(kind: .plot) != nil)
        #expect(work.document(kind: .characters) != nil)
        #expect(work.document(kind: .info) != nil)

        let snapshotsNode = work.rootNodes.first(where: { $0.name == "snapshots" })
        #expect(snapshotsNode?.kind == .folder)
        #expect(snapshotsNode?.document == nil)
    }

    @Test("ミニマルテンプレートはcontentのみを生成する")
    func minimalTemplateCreatesContentOnly() {
        let work = WorkFactory.create(title: "ミニマル作品", template: .minimal)

        #expect(work.rootNodes.count == 1)
        #expect(work.rootNodes.first?.name == "content")
        #expect(work.document(kind: .content) != nil)
        #expect(work.document(kind: .outline) == nil)
    }

    @Test("自動命名は既存作品タイトルから次の番号を採番する")
    func autoWorkTitleGeneratesNextNumber() {
        let title = makeAutoWorkTitle(
            existingTitles: ["作品1", "メモ", "作品3", "作品X", "作品10"]
        )

        #expect(title == "作品11")
    }

    @Test("自動命名は対象タイトルがない場合に作品1を返す")
    func autoWorkTitleStartsFromOne() {
        let title = makeAutoWorkTitle(existingTitles: ["下書き", "プロット"])

        #expect(title == "作品1")
    }

    @Test("作品作成後に本文を更新できる")
    func updateBodyAfterCreatingWork() {
        let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        let updatedAt = Date(timeIntervalSince1970: 1_700_000_100)
        let work = WorkFactory.create(title: "下書き", template: .standard, now: createdAt)

        let result = work.updateDocument(kind: .content, text: "第一章\nはじまり", now: updatedAt)

        #expect(result)
        #expect(work.document(kind: .content)?.text == "第一章\nはじまり")
        #expect(work.updatedAt == updatedAt)
    }

    @Test("fileNameから対象Documentを解決できる")
    func resolveDocumentByFileName() {
        let work = WorkFactory.create(title: "解決テスト", template: .standard)

        #expect(work.document(fileName: "content.md")?.kind == .content)
        #expect(work.document(fileName: "outline.md")?.kind == .outline)
        #expect(work.document(fileName: "unknown.md") == nil)
    }

    @Test("fileName指定で本文更新が反映される")
    func updateDocumentByFileName() {
        let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        let updatedAt = Date(timeIntervalSince1970: 1_700_000_200)
        let work = WorkFactory.create(title: "更新テスト", template: .standard, now: createdAt)

        let result = work.updateDocument(
            fileName: "content.md",
            text: "第二章\nつづき",
            now: updatedAt
        )

        #expect(result)
        #expect(work.document(kind: .content)?.text == "第二章\nつづき")
        #expect(work.updatedAt == updatedAt)
    }

    @Test("workID前提で更新対象を絞り、同名作品でも誤保存しない")
    func updateDocumentRequiresWorkIDContext() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let updated = Date(timeIntervalSince1970: 1_700_000_300)
        let first = WorkFactory.create(title: "同名作品", template: .standard, now: base)
        let second = WorkFactory.create(title: "同名作品", template: .standard, now: base)
        let works = [first, second]

        let missingWorkIDResult = Work.updateDocument(
            in: works,
            workID: nil,
            fileName: "content.md",
            text: "保存されない本文",
            now: updated
        )
        let updateSecondResult = Work.updateDocument(
            in: works,
            workID: second.id,
            fileName: "content.md",
            text: "保存される本文",
            now: updated
        )

        #expect(missingWorkIDResult == false)
        #expect(updateSecondResult)
        #expect(first.document(kind: .content)?.text == "")
        #expect(second.document(kind: .content)?.text == "保存される本文")
    }

    @Test("SwiftData in-memoryに作品を保存して再取得できる")
    func persistAndFetchWorkWithInMemoryContainer() throws {
        let schema = Schema([
            Work.self,
            Node.self,
            Document.self,
            Snapshot.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)

        let work = WorkFactory.create(title: "永続化テスト", template: .standard)
        _ = work.updateDocument(kind: .content, text: "保存される本文")
        context.insert(work)
        try context.save()

        let fetchedWorks = try context.fetch(FetchDescriptor<Work>())
        #expect(fetchedWorks.count == 1)
        #expect(fetchedWorks.first?.title == "永続化テスト")
        #expect(fetchedWorks.first?.document(kind: .content)?.text == "保存される本文")
    }
}
