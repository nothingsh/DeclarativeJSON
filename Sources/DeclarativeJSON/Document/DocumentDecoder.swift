import Foundation

/// Reads a document from JSON.
public struct DocumentDecoder {
    public init() {}

    /// Throws `DocumentError.unsupportedVersion` for a document of another
    /// version, and `DecodingError` when the JSON is malformed or the outline
    /// of the document is not right.
    public func decode(_ data: Data) throws -> Document {
        try JSONDecoder().decode(Document.self, from: data)
    }
}
