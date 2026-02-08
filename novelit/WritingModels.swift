import Foundation
import SwiftData

enum WorkTemplate {
    case standard
    case minimal
}

enum NodeKind: String, Codable {
    case file
    case folder
}

enum DocumentKind: String, Codable, CaseIterable {
    case content
    case outline
    case plot
    case characters
    case info

    var fileName: String {
        "\(rawValue).md"
    }

    init?(fileName: String) {
        let normalized = fileName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        switch normalized {
        case "content", "content.md":
            self = .content
        case "outline", "outline.md":
            self = .outline
        case "plot", "plot.md":
            self = .plot
        case "characters", "characters.md":
            self = .characters
        case "info", "info.md":
            self = .info
        default:
            return nil
        }
    }
}

enum SnapshotKind: String, Codable {
    case manual
    case conflict
}

struct SnapshotManifest: Codable, Equatable {
    let version: Int
    let createdAt: Date
    let files: [SnapshotManifestFile]

    func encodedJSON() throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(self)
        guard let encoded = String(data: data, encoding: .utf8) else {
            throw SnapshotManifestEncodingError.invalidUTF8
        }
        return encoded
    }
}

struct SnapshotManifestFile: Codable, Equatable {
    let fileName: String
    let text: String
}

enum SnapshotManifestBuildError: Error, Equatable {
    case emptySelection
    case unresolvedFileNames([String])
}

enum SnapshotManifestEncodingError: Error, Equatable {
    case invalidUTF8
}

@Model
final class Work {
    @Attribute(.unique) var id: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \Node.work)
    var nodes: [Node] = []

    @Relationship(deleteRule: .cascade, inverse: \Snapshot.work)
    var snapshots: [Snapshot] = []

    init(
        id: UUID = UUID(),
        title: String,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var rootNodes: [Node] {
        nodes.filter { $0.parent == nil }
    }

    func document(kind: DocumentKind) -> Document? {
        nodes
            .compactMap(\Node.document)
            .first { $0.kind == kind }
    }

    func document(fileName: String) -> Document? {
        guard let kind = DocumentKind(fileName: fileName) else {
            return nil
        }
        return document(kind: kind)
    }

    @discardableResult
    func updateDocument(kind: DocumentKind, text: String, now: Date = .now) -> Bool {
        guard let document = document(kind: kind) else {
            return false
        }

        document.text = text
        document.updatedAt = now
        document.node?.updatedAt = now
        updatedAt = now
        return true
    }

    @discardableResult
    func updateDocument(fileName: String, text: String, now: Date = .now) -> Bool {
        guard let kind = DocumentKind(fileName: fileName) else {
            return false
        }
        return updateDocument(kind: kind, text: text, now: now)
    }

    static func work(in works: [Work], id: UUID?) -> Work? {
        guard let id else {
            return nil
        }
        return works.first { $0.id == id }
    }

    static func document(in works: [Work], workID: UUID?, fileName: String) -> Document? {
        guard let work = work(in: works, id: workID) else {
            return nil
        }
        return work.document(fileName: fileName)
    }

    @discardableResult
    static func updateDocument(
        in works: [Work],
        workID: UUID?,
        fileName: String,
        text: String,
        now: Date = .now
    ) -> Bool {
        guard let work = work(in: works, id: workID) else {
            return false
        }
        return work.updateDocument(fileName: fileName, text: text, now: now)
    }

    func buildSnapshotManifest(
        selectedFileNames: Set<String>,
        createdAt: Date = .now
    ) throws -> SnapshotManifest {
        guard !selectedFileNames.isEmpty else {
            throw SnapshotManifestBuildError.emptySelection
        }

        var files: [SnapshotManifestFile] = []
        var unresolved: [String] = []

        for fileName in selectedFileNames.sorted() {
            guard let document = document(fileName: fileName) else {
                unresolved.append(fileName)
                continue
            }

            files.append(
                SnapshotManifestFile(
                    fileName: fileName,
                    text: document.text
                )
            )
        }

        guard unresolved.isEmpty else {
            throw SnapshotManifestBuildError.unresolvedFileNames(unresolved)
        }

        return SnapshotManifest(
            version: 1,
            createdAt: createdAt,
            files: files
        )
    }
}

@Model
final class Node {
    @Attribute(.unique) var id: UUID
    var name: String
    var kindRawValue: String
    var createdAt: Date
    var updatedAt: Date

    var work: Work?
    var parent: Node?

    @Relationship(deleteRule: .cascade, inverse: \Node.parent)
    var children: [Node] = []

    @Relationship(deleteRule: .cascade, inverse: \Document.node)
    var document: Document?

    var kind: NodeKind {
        get { NodeKind(rawValue: kindRawValue) ?? .file }
        set { kindRawValue = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        name: String,
        kind: NodeKind,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.kindRawValue = kind.rawValue
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class Document {
    @Attribute(.unique) var id: UUID
    var kindRawValue: String
    var text: String
    var createdAt: Date
    var updatedAt: Date

    var node: Node?

    var kind: DocumentKind {
        get { DocumentKind(rawValue: kindRawValue) ?? .content }
        set { kindRawValue = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        kind: DocumentKind,
        text: String,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.kindRawValue = kind.rawValue
        self.text = text
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class Snapshot {
    @Attribute(.unique) var id: UUID
    var title: String
    var memo: String
    var createdAt: Date
    var deviceName: String
    var kindRawValue: String
    var manifestJSON: String

    var work: Work?

    var kind: SnapshotKind {
        get { SnapshotKind(rawValue: kindRawValue) ?? .manual }
        set { kindRawValue = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        title: String,
        memo: String = "",
        createdAt: Date = .now,
        deviceName: String = "",
        kind: SnapshotKind = .manual,
        manifestJSON: String = "{}"
    ) {
        self.id = id
        self.title = title
        self.memo = memo
        self.createdAt = createdAt
        self.deviceName = deviceName
        self.kindRawValue = kind.rawValue
        self.manifestJSON = manifestJSON
    }
}

struct WorkFactory {
    static func create(
        title: String,
        template: WorkTemplate = .standard,
        now: Date = .now
    ) -> Work {
        let work = Work(title: title, createdAt: now, updatedAt: now)

        switch template {
        case .minimal:
            return work
        case .standard:
            addStandardTemplateNodes(to: work, now: now)
            return work
        }
    }

    private static func addStandardTemplateNodes(to work: Work, now: Date) {
        let contentNode = makeFileNode(name: "content", kind: .content, now: now)
        let outlineNode = makeFileNode(name: "outline", kind: .outline, now: now)
        let plotNode = makeFileNode(name: "plot", kind: .plot, now: now)
        let charactersNode = makeFileNode(name: "characters", kind: .characters, now: now)
        let infoNode = makeFileNode(name: "info", kind: .info, now: now)
        let snapshotsNode = Node(name: "snapshots", kind: .folder, createdAt: now, updatedAt: now)

        work.nodes.append(contentNode)
        work.nodes.append(outlineNode)
        work.nodes.append(plotNode)
        work.nodes.append(charactersNode)
        work.nodes.append(infoNode)
        work.nodes.append(snapshotsNode)
    }

    private static func makeFileNode(name: String, kind: DocumentKind, now: Date) -> Node {
        let node = Node(name: name, kind: .file, createdAt: now, updatedAt: now)
        let document = Document(kind: kind, text: "", createdAt: now, updatedAt: now)
        node.document = document
        return node
    }
}
