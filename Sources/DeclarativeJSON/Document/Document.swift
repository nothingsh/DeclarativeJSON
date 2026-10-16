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
        /// Rows of `columns` cells of equal width; each row as tall as its
        /// tallest cell.
        case grid
    }

    public struct Section: Equatable, Sendable {
        public let id: String
        public let layout: Layout
        /// The cells in a row of a grid, at least 1.
        public let columns: Int
        /// The space between the cells of a grid, across and down.
        public let spacing: Double
        public let header: Header?
        public let items: [Item]
        /// What the backend needs to send the items after these, such as a
        /// cursor, or nil when there are none. The library hands it to
        /// `DocumentViewController.onLoadMore` and does not read it.
        public let more: JSONValue?
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
        /// What the app's analytics need to count the item, which the library
        /// hands over without reading it; nil when the backend sent none.
        public let tracking: JSONValue?

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(String.self, forKey: .id)
            template = try container.decode(String.self, forKey: .template)
            data = try container.decodeIfPresent([String: JSONValue].self, forKey: .data) ?? [:]
            // decodeIfPresent gives nil for null.
            tracking = try container.decodeIfPresent(JSONValue.self, forKey: .tracking)
        }

        private enum CodingKeys: String, CodingKey {
            case id, template, data, tracking
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
        let templates = Self.templates(
            try container.decode([String: JSONValue].self, forKey: .templates), issues: &issues
        )

        let rawSections = try container.decode([RawSection].self, forKey: .sections)
        sections = rawSections.enumerated().map { index, raw in
            Section(raw, path: "sections[\(index)]", issues: &issues)
        }
        self.templates = templates
        self.issues = issues
    }

    /// Reads the templates of a document or a patch; a template that is not
    /// a node is left out.
    static func templates(_ raw: [String: JSONValue], issues: inout [Issue]) -> [String: Node] {
        var templates: [String: Node] = [:]
        // Sorted, so that the issues come in the same order every time.
        for name in raw.keys.sorted() {
            templates[name] = Node(raw[name]!, path: "templates.\(name)", issues: &issues)
        }
        return templates
    }

    private enum CodingKeys: String, CodingKey {
        case v, templates, sections
    }
}

extension Document.Section {
    /// Checks the layout of a section as written. A wrong value is reported
    /// and replaced by its default.
    init(_ raw: RawSection, path: String, issues: inout [Issue]) {
        var layout = Document.Layout.list
        if let name = raw.layout {
            if let known = Document.Layout(rawValue: name) {
                layout = known
            } else {
                issues.append(Issue(.unknownLayout(name), at: path))
            }
        }
        var columns = 2
        var spacing = 0.0
        if layout == .grid {
            switch raw.columns {
            case nil, .null?:
                break
            case .number(let number)? where Int(exactly: number).map({ $0 >= 1 }) == true:
                columns = Int(number)
            case _?:
                issues.append(Issue(.typeMismatch(property: "columns", expected: .integer), at: path))
            }
            switch raw.spacing {
            case nil, .null?:
                break
            case .number(let number)? where number.isFinite && number >= 0:
                spacing = number
            case _?:
                issues.append(Issue(.typeMismatch(property: "spacing", expected: .number), at: path))
            }
        }
        self.init(
            id: raw.id, layout: layout, columns: columns, spacing: spacing, header: raw.header, items: raw.items,
            more: raw.more
        )
    }
}

/// A section as written, before its layout is checked.
struct RawSection: Decodable {
    let id: String
    let layout: String?
    // Checked by the document, so that a wrong value does not fail it.
    let columns: JSONValue?
    let spacing: JSONValue?
    let header: Document.Header?
    let items: [Document.Item]
    // decodeIfPresent gives nil for null, so `"more": null` is no more.
    let more: JSONValue?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        layout = try container.decodeIfPresent(String.self, forKey: .layout)
        columns = try container.decodeIfPresent(JSONValue.self, forKey: .columns)
        spacing = try container.decodeIfPresent(JSONValue.self, forKey: .spacing)
        header = try container.decodeIfPresent(Document.Header.self, forKey: .header)
        items = try container.decodeIfPresent([Document.Item].self, forKey: .items) ?? []
        more = try container.decodeIfPresent(JSONValue.self, forKey: .more)
    }

    private enum CodingKeys: String, CodingKey {
        case id, layout, columns, spacing, header, items, more
    }
}
