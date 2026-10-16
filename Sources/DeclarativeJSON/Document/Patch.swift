import Foundation

/// The operations of a patch, by their `op`.
enum PatchOperationName: String, CaseIterable {
    case replaceItems, insertItems, removeItems, replaceSections, insertSections, removeSections
}

/// A change to part of a page: items and sections to replace, insert or
/// remove, by `id`, and templates to add.
///
/// ```json
/// { "v": 1,
///   "templates": { "notice": { "type": "label", "text": "$text" } },
///   "operations": [
///     { "op": "replaceItems", "items": [ { "id": "p1", "template": "product", "data": { … } } ] },
///     { "op": "insertItems", "section": "feed", "after": "p9", "items": [ … ] },
///     { "op": "removeSections", "ids": ["ads"] }
///   ] }
/// ```
///
/// As with a document, the outline has to be right: `v`, `operations`, the
/// `op` of each operation and what it takes. An operation this version does
/// not know is skipped and reported in `issues`.
public struct Patch: Equatable, Sendable {
    /// Templates to add to the page. One with the name of a template the page
    /// has replaces it.
    public let templates: [String: Node]
    public let operations: [Operation]
    /// What was wrong in the patch and how it was worked around.
    public let issues: [Issue]
    /// Where each operation is in the patch, for the issues of applying it.
    let paths: [String]

    public enum Operation: Equatable, Sendable {
        /// Replaces the items of the same `id`, in their place.
        case replaceItems([Document.Item])
        /// Inserts items into a section after the item `after`, or first in
        /// the section without it.
        case insertItems([Document.Item], section: String, after: String?)
        /// Removes the items of these `id`s.
        case removeItems([String])
        /// Replaces the sections of the same `id`, in their place, with their
        /// header and items.
        case replaceSections([Document.Section])
        /// Inserts sections after the section `after`, or first in the page
        /// without it.
        case insertSections([Document.Section], after: String?)
        /// Removes the sections of these `id`s, with their items.
        case removeSections([String])
    }
}

extension Patch: Decodable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decode(Int.self, forKey: .v)
        guard version == DocumentVersion.current else {
            throw DocumentError.unsupportedVersion(version)
        }

        var issues: [Issue] = []
        templates = Document.templates(
            try container.decodeIfPresent([String: JSONValue].self, forKey: .templates) ?? [:], issues: &issues
        )
        var operations: [Operation] = []
        var paths: [String] = []
        var list = try container.nestedUnkeyedContainer(forKey: .operations)
        while !list.isAtEnd {
            let path = "operations[\(list.currentIndex)]"
            let fields = try list.nestedContainer(keyedBy: OperationKeys.self)
            let name = try fields.decode(String.self, forKey: .op)
            func items() throws -> [Document.Item] {
                try fields.decode([Document.Item].self, forKey: .items)
            }
            func sections() throws -> [Document.Section] {
                try fields.decode([RawSection].self, forKey: .sections).enumerated().map { index, raw in
                    Document.Section(raw, path: "\(path).sections[\(index)]", issues: &issues)
                }
            }
            func ids() throws -> [String] {
                try fields.decode([String].self, forKey: .ids)
            }
            func after() throws -> String? {
                try fields.decodeIfPresent(String.self, forKey: .after)
            }

            switch PatchOperationName(rawValue: name) {
            case .replaceItems?:
                operations.append(.replaceItems(try items()))
            case .insertItems?:
                operations.append(.insertItems(
                    try items(), section: try fields.decode(String.self, forKey: .section), after: try after()
                ))
            case .removeItems?:
                operations.append(.removeItems(try ids()))
            case .replaceSections?:
                operations.append(.replaceSections(try sections()))
            case .insertSections?:
                operations.append(.insertSections(try sections(), after: try after()))
            case .removeSections?:
                operations.append(.removeSections(try ids()))
            case nil:
                issues.append(Issue(.unknownOperation(name), at: path))
                continue
            }
            paths.append(path)
        }
        self.operations = operations
        self.paths = paths
        self.issues = issues
    }

    private enum CodingKeys: String, CodingKey {
        case v, templates, operations
    }

    private enum OperationKeys: String, CodingKey {
        case op, items, section, after, ids, sections
    }
}

/// A document with a patch applied, and what the patch changed.
struct PatchResult {
    let document: Document
    /// What in the patch could not be applied. It was skipped.
    let issues: [Issue]
    /// The items, and the sections whose headers, have the patch's data.
    let changedItems: Set<String>
    let changedSections: Set<String>
}

extension Document {
    /// Applies a patch's operations in order. An operation that refers to an
    /// `id` the document does not have, or an item or section that the page
    /// could not show, is skipped where it is at fault: an item or section, or
    /// the whole operation when it is where to insert.
    func applying(_ patch: Patch) -> PatchResult {
        let templates = self.templates.merging(patch.templates) { $1 }
        var sections = self.sections
        var issues: [Issue] = []
        var changedItems: Set<String> = []
        var changedSections: Set<String> = []

        func locate(_ id: String) -> (section: Int, item: Int)? {
            for (index, section) in sections.enumerated() {
                if let item = section.items.firstIndex(where: { $0.id == id }) {
                    return (index, item)
                }
            }
            return nil
        }
        func itemIDs(outside section: String? = nil) -> Set<String> {
            Set(sections.filter { $0.id != section }.flatMap { $0.items.map(\.id) })
        }
        // Whether the page can show an item the patch adds, as when it shows a
        // document; `taken` gets its id.
        func accepts(_ item: Item, path: String, taken: inout Set<String>) -> Bool {
            if taken.contains(item.id) {
                issues.append(Issue(.duplicateID(item.id), at: path))
            } else if templates[item.template] == nil {
                issues.append(Issue(.unknownTemplate(item.template), at: path))
            } else {
                taken.insert(item.id)
                return true
            }
            return false
        }
        // A section the patch adds, without the header and items the page
        // could not show.
        func checked(_ section: Section, path: String) -> Section {
            var header = section.header
            if let written = header, templates[written.template] == nil {
                issues.append(Issue(.unknownTemplate(written.template), at: "\(path).header"))
                header = nil
            }
            var taken = itemIDs(outside: section.id)
            let items = section.items.enumerated()
                .filter { accepts($1, path: "\(path).items[\($0)]", taken: &taken) }
                .map(\.element)
            changedSections.insert(section.id)
            changedItems.formUnion(items.map(\.id))
            return Section(
                id: section.id, layout: section.layout, columns: section.columns, spacing: section.spacing,
                header: header, items: items
            )
        }

        for (operation, path) in zip(patch.operations, patch.paths) {
            switch operation {
            case .replaceItems(let items):
                for (index, item) in items.enumerated() {
                    let itemPath = "\(path).items[\(index)]"
                    guard let location = locate(item.id) else {
                        issues.append(Issue(.unknownID(item.id), at: itemPath))
                        continue
                    }
                    guard templates[item.template] != nil else {
                        issues.append(Issue(.unknownTemplate(item.template), at: itemPath))
                        continue
                    }
                    var list = sections[location.section].items
                    list[location.item] = item
                    sections[location.section] = sections[location.section].with(items: list)
                    changedItems.insert(item.id)
                }

            case .insertItems(let items, let sectionID, let after):
                guard let index = sections.firstIndex(where: { $0.id == sectionID }) else {
                    issues.append(Issue(.unknownID(sectionID), at: "\(path).section"))
                    continue
                }
                var list = sections[index].items
                var position = 0
                if let after {
                    guard let item = list.firstIndex(where: { $0.id == after }) else {
                        issues.append(Issue(.unknownID(after), at: "\(path).after"))
                        continue
                    }
                    position = item + 1
                }
                var taken = itemIDs()
                for (itemIndex, item) in items.enumerated()
                where accepts(item, path: "\(path).items[\(itemIndex)]", taken: &taken) {
                    list.insert(item, at: position)
                    position += 1
                    changedItems.insert(item.id)
                }
                sections[index] = sections[index].with(items: list)

            case .removeItems(let ids):
                for (index, id) in ids.enumerated() {
                    guard let location = locate(id) else {
                        issues.append(Issue(.unknownID(id), at: "\(path).ids[\(index)]"))
                        continue
                    }
                    var list = sections[location.section].items
                    list.remove(at: location.item)
                    sections[location.section] = sections[location.section].with(items: list)
                }

            case .replaceSections(let replacements):
                for (index, section) in replacements.enumerated() {
                    let sectionPath = "\(path).sections[\(index)]"
                    guard let position = sections.firstIndex(where: { $0.id == section.id }) else {
                        issues.append(Issue(.unknownID(section.id), at: sectionPath))
                        continue
                    }
                    sections[position] = checked(section, path: sectionPath)
                }

            case .insertSections(let inserted, let after):
                var position = 0
                if let after {
                    guard let index = sections.firstIndex(where: { $0.id == after }) else {
                        issues.append(Issue(.unknownID(after), at: "\(path).after"))
                        continue
                    }
                    position = index + 1
                }
                for (index, section) in inserted.enumerated() {
                    let sectionPath = "\(path).sections[\(index)]"
                    guard !sections.contains(where: { $0.id == section.id }) else {
                        issues.append(Issue(.duplicateID(section.id), at: sectionPath))
                        continue
                    }
                    sections.insert(checked(section, path: sectionPath), at: position)
                    position += 1
                }

            case .removeSections(let ids):
                for (index, id) in ids.enumerated() {
                    guard let position = sections.firstIndex(where: { $0.id == id }) else {
                        issues.append(Issue(.unknownID(id), at: "\(path).ids[\(index)]"))
                        continue
                    }
                    sections.remove(at: position)
                }
            }
        }

        return PatchResult(
            document: Document(templates: templates, sections: sections, issues: self.issues),
            issues: issues,
            changedItems: changedItems,
            changedSections: changedSections
        )
    }
}

private extension Document.Section {
    func with(items: [Document.Item]) -> Self {
        Self(id: id, layout: layout, columns: columns, spacing: spacing, header: header, items: items)
    }
}
