import Foundation

/// Why a document could not be decoded, besides malformed JSON and missing
/// keys, which throw `DecodingError`.
public enum DocumentError: Error, Equatable {
    /// The document's `v` is not `DocumentVersion.current`.
    case unsupportedVersion(Int)
}

/// A page: the cell templates and the sections of items that use them.
///
/// The outline has to be right: `v`, the template names, and the `id` and
/// `template` of every section and item. Inside a template, a node that is not
/// one is left out and reported in `issues` instead of failing the document.
public struct Document: Equatable, Sendable {
    public let templates: [String: Node]
    public let sections: [Section]
    /// What was wrong in the document and how it was worked around.
    public let issues: [Issue]

    public enum Layout: String, Equatable, Sendable {
        /// One column; each cell as tall as its content.
        case list
        /// One row that scrolls sideways.
        case carousel
    }

    public struct Section: Equatable, Sendable {
        public let id: String
        public let layout: Layout
        public let header: Header?
        public let items: [Item]
    }

    /// A section header: a template and the data it shows.
    public struct Header: Equatable, Sendable, Decodable {
        public let template: String
        public let data: [String: JSONValue]

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            template = try container.decode(String.self, forKey: .template)
            data = try container.decodeIfPresent([String: JSONValue].self, forKey: .data) ?? [:]
        }

        private enum CodingKeys: String, CodingKey {
            case template, data
        }
    }

    /// A cell: a template and the data it shows. `id` identifies the item
    /// within the page.
    public struct Item: Equatable, Sendable, Decodable {
        public let id: String
        public let template: String
        public let data: [String: JSONValue]

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(String.self, forKey: .id)
            template = try container.decode(String.self, forKey: .template)
            data = try container.decodeIfPresent([String: JSONValue].self, forKey: .data) ?? [:]
        }

        private enum CodingKeys: String, CodingKey {
            case id, template, data
        }
    }
}

extension Document: Decodable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // The version first, so that a document of another version fails on
        // its version rather than on whatever else changed.
        let version = try container.decode(Int.self, forKey: .v)
        guard version == DocumentVersion.current else {
            throw DocumentError.unsupportedVersion(version)
        }

        var issues: [Issue] = []
        let rawTemplates = try container.decode([String: JSONValue].self, forKey: .templates)
        var templates: [String: Node] = [:]
        // Sorted, so that the issues come in the same order every time.
        for name in rawTemplates.keys.sorted() {
            templates[name] = Node(rawTemplates[name]!, path: "templates.\(name)", issues: &issues)
        }

        let rawSections = try container.decode([RawSection].self, forKey: .sections)
        sections = rawSections.enumerated().map { index, raw in
            var layout = Layout.list
            if let name = raw.layout {
                if let known = Layout(rawValue: name) {
                    layout = known
                } else {
                    issues.append(Issue(.unknownLayout(name), at: "sections[\(index)]"))
                }
            }
            return Section(id: raw.id, layout: layout, header: raw.header, items: raw.items)
        }
        self.templates = templates
        self.issues = issues
    }

    private enum CodingKeys: String, CodingKey {
        case v, templates, sections
    }
}

/// A section as written, before its layout is checked.
private struct RawSection: Decodable {
    let id: String
    let layout: String?
    let header: Document.Header?
    let items: [Document.Item]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        layout = try container.decodeIfPresent(String.self, forKey: .layout)
        header = try container.decodeIfPresent(Document.Header.self, forKey: .header)
        items = try container.decodeIfPresent([Document.Item].self, forKey: .items) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case id, layout, header, items
    }
}
