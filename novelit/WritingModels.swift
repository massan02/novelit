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
}

enum SnapshotKind: String, Codable {
    case manual
    case conflict
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
