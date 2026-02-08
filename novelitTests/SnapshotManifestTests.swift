import Foundation
import Testing
@testable import novelit

struct SnapshotManifestTests {
    @Test("選択したファイルだけでmanifestを生成できる")
    func buildManifestFromSelectedFiles() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let work = WorkFactory.create(title: "manifest生成", template: .standard, now: now)
        _ = work.updateDocument(fileName: "content.md", text: "本文", now: now)
        _ = work.updateDocument(fileName: "outline.md", text: "アウトライン", now: now)

        let manifest = try work.buildSnapshotManifest(
            selectedFileNames: ["outline.md", "content.md"],
            createdAt: now
        )

        #expect(manifest.version == 1)
        #expect(manifest.createdAt == now)
        #expect(manifest.files.count == 2)
        #expect(manifest.files[0] == SnapshotManifestFile(fileName: "content.md", text: "本文"))
        #expect(manifest.files[1] == SnapshotManifestFile(fileName: "outline.md", text: "アウトライン"))
    }

    @Test("未選択ではmanifest生成エラーを返す")
    func emptySelectionReturnsBuildError() {
        let work = WorkFactory.create(title: "manifest未選択", template: .standard)

        var captured: SnapshotManifestBuildError?
        do {
            _ = try work.buildSnapshotManifest(selectedFileNames: [])
        } catch let error as SnapshotManifestBuildError {
            captured = error
        } catch {
            captured = nil
        }

        #expect(captured == .emptySelection)
    }

    @Test("未知ファイル名が混ざるとmanifest生成エラーを返す")
    func unresolvedFileNameReturnsBuildError() {
        let work = WorkFactory.create(title: "manifest未知ファイル", template: .standard)

        var captured: SnapshotManifestBuildError?
        do {
            _ = try work.buildSnapshotManifest(
                selectedFileNames: ["content.md", "unknown.md"]
            )
        } catch let error as SnapshotManifestBuildError {
            captured = error
        } catch {
            captured = nil
        }

        #expect(captured == .unresolvedFileNames(["unknown.md"]))
    }

    @Test("manifestをJSONエンコードして復元できる")
    func manifestJSONRoundTrip() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_100)
        let manifest = SnapshotManifest(
            version: 1,
            createdAt: now,
            files: [
                SnapshotManifestFile(fileName: "content.md", text: "本文"),
                SnapshotManifestFile(fileName: "plot.md", text: "プロット")
            ]
        )

        let json = try manifest.encodedJSON()

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(SnapshotManifest.self, from: Data(json.utf8))

        #expect(decoded == manifest)
    }
}
